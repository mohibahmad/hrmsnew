import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/validators.dart';
import '../utils/worker_identity.dart';
import 'auth_service.dart';
import 'dummy_data.dart';
import 'time_off_service.dart';

class BulkWorkerResult {
  final int imported;
  final int skipped;
  final List<String> skipReasons;
  BulkWorkerResult({
    required this.imported,
    required this.skipped,
    this.skipReasons = const [],
  });
}

class FirestoreService {
  static bool isTesting = false;
  static FirestoreService? _instance;
  static FirestoreService get instance => _instance!;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  FirestoreService() {
    _instance = this;
  }

  Map<String, dynamic> _withNormalizedCurrency(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized.containsKey('currency')) {
      normalized['currency'] = CurrencyUtils.normalize(normalized['currency']);
    }
    return normalized;
  }

  String get _userKey {
    final user = AuthService.instance.currentUser;
    if (user == null) return '';

    final uid = user.uid;
    if (uid.isNotEmpty && uid != 'guest_uid' && !uid.startsWith('guest_')) {
      return uid;
    }

    return '';
  }

  bool get hasValidUserKey => _userKey.isNotEmpty;

  DocumentReference? get _userDoc {
    final key = _userKey;
    if (key.isEmpty) return null;
    return _db.collection('hrms_user').doc(key);
  }

  CollectionReference? get _workers => _userDoc?.collection('hrms_workers');
  CollectionReference? get _expenses => _userDoc?.collection('hrms_expenses');
  CollectionReference? get _attendance =>
      _userDoc?.collection('hrms_attendance');
  CollectionReference? get _payroll => _userDoc?.collection('hrms_payroll');
  CollectionReference? get _timeoff => _userDoc?.collection('hrms_timeoff');
  CollectionReference? get _assets => _userDoc?.collection('hrms_assets');
  CollectionReference? get _holidays => _userDoc?.collection('hrms_holidays');
  CollectionReference? get _notifications =>
      _userDoc?.collection('hrms_notifications');

  Future<void> createUserProfile({
    required String username,
    required String email,
    required String phone,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null ||
        user.isAnonymous ||
        user.uid == 'guest_uid' ||
        user.uid.startsWith('guest_')) {
      return;
    }

    final doc = _db.collection('hrms_user').doc(user.uid);

    await doc.set({
      'username': username,
      'email': email,
      'phone': phone,
      'uid': user.uid,
      'companyId': '',
      'hasDummyData': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    final doc = _userDoc;
    if (doc == null) return;
    await doc.set(_withNormalizedCurrency(data), SetOptions(merge: true));
  }

  Future<void> deleteUserData() async {
    final doc = _userDoc;
    if (doc == null) return;
    await doc.set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearDummyDataForCurrentUser() async {
    if (isTesting) return;
    final doc = _userDoc;
    if (doc == null) return;

    final profile = await getUserProfile();
    if (profile?['hasDummyData'] != true) return;

    for (final collectionName in [
      'hrms_workers',
      'hrms_expenses',
      'hrms_attendance',
      'hrms_payroll',
      'hrms_timeoff',
      'hrms_assets',
      'hrms_holidays',
    ]) {
      final snapshot = await doc.collection(collectionName).get();
      var batch = _db.batch();
      int count = 0;
      for (final d in snapshot.docs) {
        batch.delete(d.reference);
        count++;
        if (count % 500 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      }
      if (count % 500 != 0 && count > 0) {
        await batch.commit();
      }
    }

    await doc.update({'hasDummyData': false});
  }

  Future<bool> isCurrentUserDeleted() async {
    final profile = await getUserProfile();
    return profile?['isDeleted'] == true;
  }

  Future<bool> isEmailDeleted(String email) async {
    if (email.trim().isEmpty) return false;
    final snapshot = await _db
        .collection('hrms_user')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return false;
    return snapshot.docs.first.data()['isDeleted'] == true;
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    if (isTesting) return {'isPremium': false, 'hasDummyData': false};
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snapshot = await doc.get();
      return snapshot.data() as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  
  Stream<Map<String, dynamic>?> get userProfileStream {
    final doc = _userDoc;
    if (doc == null) return Stream.value(null);
    return doc.snapshots().map((snap) => snap.data() as Map<String, dynamic>?);
  }

  Future<String> addWorker(Map<String, dynamic> worker) async {
    Validators.validateWorker(worker);
    final coll = _workers;
    if (coll == null) throw StateError('No authenticated user');
    final existingSnapshot = await coll.get();
    final existingWorkers = existingSnapshot.docs.map(
      (doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id},
    );
    final duplicateField = WorkerIdentity.duplicateField(
      worker,
      existingWorkers,
    );
    if (duplicateField != null) {
      throw DuplicateWorkerException(duplicateField);
    }
    final docRef = await coll.add({
      ..._withNormalizedCurrency(worker),
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (worker['name'] ?? '').toString();
    if (name.isNotEmpty) {
      await addNotification({
        'type': 'worker_added',
        'title': 'notif_title_new_member'.tr(namedArgs: {'name': name}),
        'message': 'notif_msg_new_member'.tr(namedArgs: {'name': name}),
        'data': {'name': name},
      });
    }
    return docRef.id;
  }

  Future<BulkWorkerResult> addBulkWorkers(
    List<Map<String, dynamic>> workersList,
  ) async {
    final coll = _workers;
    if (coll == null)
      return BulkWorkerResult(imported: 0, skipped: workersList.length);
    var batch = _db.batch();
    int count = 0;
    int skipped = 0;
    final existingSnapshot = await coll.get();
    final existingWorkers = existingSnapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();
    final acceptedWorkers = <Map<String, dynamic>>[];

    final skipReasons = <String>[];
    for (var worker in workersList) {
      try {
        Validators.validateWorker(worker);
        final duplicateField = WorkerIdentity.duplicateField(worker, [
          ...existingWorkers,
          ...acceptedWorkers,
        ]);
        if (duplicateField != null) {
          skipped++;
          skipReasons.add('Duplicate ${duplicateField.name}: ${worker['name'] ?? worker['email'] ?? ''}');
          continue;
        }
        final docRef = coll.doc();
        batch.set(docRef, {
          ..._withNormalizedCurrency(worker),
          'createdAt': FieldValue.serverTimestamp(),
        });
        acceptedWorkers.add(worker);
        count++;

        if (count % 500 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      } catch (e) {
        skipped++;
        skipReasons.add('Validation error: ${e.toString().substring(0, 100)}');
        continue;
      }
    }

    if (count % 500 != 0 && count > 0) {
      await batch.commit();
    }

    if (count > 0) {
      await addNotification({
        'type': 'worker_added',
        'title': 'notif_title_bulk_workers'.tr(),
        'message': 'notif_msg_bulk_workers'.tr(namedArgs: {'count': '$count'}),
        'data': {'count': '$count'},
      });
    }

    return BulkWorkerResult(imported: count, skipped: skipped, skipReasons: skipReasons);
  }

  Future<void> updateWorker(String id, Map<String, dynamic> data) async {
    Validators.validateWorker(data);
    final coll = _workers;
    if (coll == null) return;
    await coll.doc(id).update(_withNormalizedCurrency(data));
  }

  
  Future<void> updateWorkerLeaves(
    String id,
    Map<String, dynamic> leaveData,
  ) async {
    final coll = _workers;
    if (coll == null || id.isEmpty) return;
    await coll.doc(id).update(leaveData);
  }

  Future<void> deleteWorker(String id) async {
    final coll = _workers;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get workersStream {
    final coll = _workers;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<QuerySnapshot> getWorkersOnce() async {
    final coll = _workers;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.get();
  }

  Future<String> addExpense(Map<String, dynamic> expense) async {
    Validators.validateExpense(expense);
    final coll = _expenses;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...expense,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final category = (expense['category'] ?? expense['type'] ?? '').toString();
    final amount = (expense['amount'] ?? '').toString();
    await addNotification({
      'type': 'expense_added',
      'title': category.isNotEmpty
          ? 'notif_title_expense_category'.tr(namedArgs: {'category': category})
          : 'notif_title_expense'.tr(),
      'message': amount.isNotEmpty
          ? 'notif_msg_expense_amount'.tr(namedArgs: {'amount': '\$$amount'})
          : 'notif_msg_expense'.tr(),
      'data': {
        'category': category,
        'amount': amount.isNotEmpty ? '\$$amount' : '',
      },
    });
    return docRef.id;
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    Validators.validateExpense(data);
    final coll = _expenses;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  
  Future<void> upsertPayrollExpense(
    Map<String, dynamic> expense, {
    required String payrollKey,
  }) async {
    Validators.validateExpense(expense);
    final coll = _expenses;
    if (coll == null) throw StateError('No authenticated user');
    final existing = await coll
        .where('payrollKey', isEqualTo: payrollKey)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await addExpense({...expense, 'payrollKey': payrollKey});
      return;
    }
    await existing.docs.first.reference.update({
      ...expense,
      'payrollKey': payrollKey,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteExpense(String id) async {
    final coll = _expenses;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get expensesStream {
    final coll = _expenses;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<String> addAttendanceRecord(Map<String, dynamic> record) async {
    Validators.validateAttendance(record);
    final coll = _attendance;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (record['name'] ?? record['workerName'] ?? '').toString();
    if (name.isNotEmpty) {
      await addNotification({
        'type': 'attendance_marked',
        'title': 'notif_title_attendance'.tr(namedArgs: {'name': name}),
        'message': 'notif_msg_attendance'.tr(namedArgs: {'name': name}),
        'data': {'name': name},
      });
    }
    return docRef.id;
  }

  Future<void> updateAttendanceRecord(
    String id,
    Map<String, dynamic> data,
  ) async {
    Validators.validateAttendance(data);
    final coll = _attendance;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> deleteAttendanceRecord(String id) async {
    final coll = _attendance;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  DateTime? _dateFromCreatedAt(dynamic createdAt) {
    if (createdAt == null) return null;
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is DateTime) return createdAt;
    return AppDateUtils.parseDateString(createdAt.toString());
  }

  
  Future<Map<String, int>> getWorkerMonthlyAttendance(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    final now = DateTime.now();
    List<Map<String, dynamic>> records;
    final isGuest = AuthService.instance.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      records = List<Map<String, dynamic>>.from(DummyData.attendance);
    } else {
      final coll = _attendance;
      if (coll == null) return {'absents': 0, 'leaves': 0};

      
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

      final snap = await coll
          .where('email', isEqualTo: normalizedEmail)
          .where('createdAt', isGreaterThanOrEqualTo: startOfMonth)
          .where('createdAt', isLessThan: startOfNextMonth)
          .get();

      records = snap.docs
          .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
          .toList();
    }

    final absentDates = <DateTime>{};
    final legacyLeaveDates = <DateTime>{};
    final seenDays = <String>{};
    for (final att in records) {
      final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
      if (normalizedEmail.isNotEmpty && attEmail != normalizedEmail) continue;
      final date = _dateFromCreatedAt(att['createdAt']);
      if (date == null) continue;
      if (date.year != now.year || date.month != now.month) continue;
      final dayKey = '$attEmail-${date.year}-${date.month}-${date.day}';
      if (seenDays.contains(dayKey)) continue;
      seenDays.add(dayKey);
      final status = (att['status'] ?? '').toString();
      if (status == 'Absent') {
        absentDates.add(DateTime(date.year, date.month, date.day));
      } else if (status == 'Leave') {
        legacyLeaveDates.add(DateTime(date.year, date.month, date.day));
      }
    }

    final List<Map<String, dynamic>> timeOffRecords;
    if (isGuest) {
      timeOffRecords = List<Map<String, dynamic>>.from(DummyData.timeoff);
    } else {
      final coll = _timeoff;
      if (coll == null) {
        timeOffRecords = const [];
      } else {
        final snapshot = await coll.get();
        timeOffRecords = snapshot.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList();
      }
    }

    final worker = <String, dynamic>{'email': normalizedEmail};
    final planned = TimeOffService.monthlyLeaveCounts(
      worker,
      timeOffRecords,
      month: now,
    );
    final nonDuplicateLegacyPaid = legacyLeaveDates
        .where(
          (date) => !TimeOffService.isWorkerOnLeave(
            worker,
            timeOffRecords,
            onDate: date,
          ),
        )
        .length;
    absentDates.removeWhere(
      (date) =>
          TimeOffService.isWorkerOnLeave(worker, timeOffRecords, onDate: date),
    );

    
    final holidayDates = await _getHolidayDatesForMonth(now.year, now.month);
    absentDates.removeWhere((date) => holidayDates.contains(date));

    final paidLeaves = (planned['paidLeaves'] ?? 0) + nonDuplicateLegacyPaid;
    final unpaidLeaves = planned['unpaidLeaves'] ?? 0;
    return {
      'absents': absentDates.length,
      'paidLeaves': paidLeaves,
      'unpaidLeaves': unpaidLeaves,
      'leaves': paidLeaves + unpaidLeaves,
    };
  }

  
  Future<int> getMonthlyWorkingDays({DateTime? month}) async {
    final now = month ?? DateTime.now();
    final year = now.year;
    final m = now.month;
    final daysInMonth = DateTime(year, m + 1, 0).day;

    
    int weekdays = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, m, d);
      if (date.weekday != DateTime.sunday) weekdays++;
    }

    
    final coll = _holidays;
    if (coll == null) return weekdays;
    try {
      final snap = await coll.get();
      int holidayCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['isEnabled'] == false) continue;
        final hDay = int.tryParse((data['day'] ?? '').toString());
        final hMonthStr = (data['month'] ?? '').toString();
        final hMonth = _parseMonthString(hMonthStr);
        if (hMonth == m && hDay != null && hDay >= 1 && hDay <= daysInMonth) {
          final hDate = DateTime(year, m, hDay);
          if (hDate.weekday != DateTime.sunday) holidayCount++;
        }
      }
      return (weekdays - holidayCount).clamp(0, weekdays);
    } catch (_) {
      return weekdays;
    }
  }

  static int _parseMonthString(String month) {
    const months = {
      'january': 1, 'february': 2, 'march': 3, 'april': 4,
      'may': 5, 'june': 6, 'july': 7, 'august': 8,
      'september': 9, 'october': 10, 'november': 11, 'december': 12,
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
      'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    return months[month.toLowerCase()] ?? 0;
  }

  Future<Set<DateTime>> _getHolidayDatesForMonth(int year, int month) async {
    final dates = <DateTime>{};
    final coll = _holidays;
    if (coll == null) return dates;
    try {
      final snap = await coll.get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['isEnabled'] == false) continue;
        final hDay = int.tryParse((data['day'] ?? '').toString());
        final hMonth = _parseMonthString((data['month'] ?? '').toString());
        if (hMonth == month && hDay != null && hDay >= 1 && hDay <= 31) {
          dates.add(DateTime(year, month, hDay));
        }
      }
    } catch (_) {}
    return dates;
  }

  Stream<QuerySnapshot> get attendanceStream {
    final coll = _attendance;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<String> addPayrollRecord(Map<String, dynamic> record) async {
    Validators.validatePayroll(record);
    final coll = _payroll;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (record['name'] ?? '').toString();
    final amount = (record['netSalary'] ?? record['salary'] ?? '').toString();
    if (name.isNotEmpty) {
      await addNotification({
        'type': 'payroll_added',
        'title': 'notif_title_payroll'.tr(namedArgs: {'name': name}),
        'message': amount.isNotEmpty
            ? 'notif_msg_payroll_amount'.tr(
                namedArgs: {'amount': '\$$amount', 'name': name},
              )
            : 'notif_msg_payroll'.tr(namedArgs: {'name': name}),
        'data': {'name': name, 'amount': amount.isNotEmpty ? '\$$amount' : ''},
      });
    }
    return docRef.id;
  }

  
  Future<int> addBulkPayrollRecords(List<Map<String, dynamic>> records) async {
    final coll = _payroll;
    if (coll == null) return 0;
    var batch = _db.batch();
    int count = 0;
    for (final record in records) {
      try {
        Validators.validatePayroll(record);
        final docRef = coll.doc();
        batch.set(docRef, {
          ...record,
          'createdAt': FieldValue.serverTimestamp(),
        });
        count++;
        if (count % 500 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      } catch (_) {
        
      }
    }
    if (count % 500 != 0 && count > 0) {
      await batch.commit();
    }
    return count;
  }

  
  Future<void> addBulkExpenses(List<Map<String, dynamic>> expenses) async {
    final coll = _expenses;
    if (coll == null) return;
    var batch = _db.batch();
    int count = 0;
    for (final expense in expenses) {
      try {
        Validators.validateExpense(expense);
        final docRef = coll.doc();
        batch.set(docRef, {
          ...expense,
          'createdAt': FieldValue.serverTimestamp(),
        });
        count++;
        if (count % 500 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      } catch (_) {}
    }
    if (count % 500 != 0 && count > 0) {
      await batch.commit();
    }
  }

  
  Future<void> addBulkNotifications(
    List<Map<String, dynamic>> notifications,
  ) async {
    final coll = _notifications;
    if (coll == null) return;
    var batch = _db.batch();
    int count = 0;
    for (final notification in notifications) {
      final docRef = coll.doc();
      batch.set(docRef, {
        ...notification,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    if (count % 500 != 0 && count > 0) {
      await batch.commit();
    }
  }

  Future<void> updatePayrollRecord(String id, Map<String, dynamic> data) async {
    final coll = _payroll;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> deletePayrollRecord(String id) async {
    final coll = _payroll;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get payrollStream {
    final coll = _payroll;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<String> addTimeOffRecord(Map<String, dynamic> record) async {
    Validators.validateTimeOff(record);
    final coll = _timeoff;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (record['workerName'] ?? record['name'] ?? '').toString();
    final type = (record['type'] ?? record['leaveType'] ?? 'Leave').toString();
    if (name.isNotEmpty) {
      await addNotification({
        'type': 'time_off_added',
        'title': 'notif_title_time_off'.tr(namedArgs: {'name': name}),
        'message': 'notif_msg_time_off'.tr(
          namedArgs: {'type': type, 'name': name},
        ),
        'data': {'name': name, 'type': type},
      });
    }
    return docRef.id;
  }

  Future<void> updateTimeOffRecord(String id, Map<String, dynamic> data) async {
    final coll = _timeoff;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  
  Future<String> saveTimeOffWithWorkerBalance({
    String? timeOffId,
    required Map<String, dynamic> record,
    required String workerId,
    required Map<String, dynamic> balance,
  }) async {
    Validators.validateTimeOff(record);
    final timeOffColl = _timeoff;
    final workersColl = _workers;
    if (timeOffColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }
    final isNew = timeOffId == null || timeOffId.isEmpty;
    final timeOffRef = isNew ? timeOffColl.doc() : timeOffColl.doc(timeOffId);
    final batch = _db.batch();
    batch.set(timeOffRef, {
      ...record,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(workersColl.doc(workerId), balance, SetOptions(merge: true));
    await batch.commit();

    if (isNew) {
      final name = (record['workerName'] ?? record['name'] ?? '').toString();
      final type = (record['type'] ?? record['leaveType'] ?? 'Leave')
          .toString();
      if (name.isNotEmpty) {
        await addNotification({
          'type': 'time_off_added',
          'title': 'notif_title_time_off'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_time_off'.tr(
            namedArgs: {'type': type, 'name': name},
          ),
          'data': {'name': name, 'type': type},
        });
      }
    }
    return timeOffRef.id;
  }

  Future<void> deleteTimeOffRecord(String id) async {
    final coll = _timeoff;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Future<void> deleteTimeOffWithWorkerBalance({
    required String timeOffId,
    required String workerId,
    required Map<String, dynamic> balance,
  }) async {
    final timeOffColl = _timeoff;
    final workersColl = _workers;
    if (timeOffColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }
    final batch = _db.batch();
    batch.delete(timeOffColl.doc(timeOffId));
    batch.set(workersColl.doc(workerId), balance, SetOptions(merge: true));
    await batch.commit();
  }

  Stream<QuerySnapshot> get timeoffStream {
    final coll = _timeoff;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  
  Future<String> addAsset(Map<String, dynamic> asset) async {
    Validators.validateAsset(asset);
    final coll = _assets;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...asset,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final workerName = (asset['name'] ?? asset['assetName'] ?? '').toString();
    final assetType = (asset['type'] ?? asset['assetType'] ?? '').toString();
    if (workerName.isNotEmpty) {
      await addNotification({
        'type': 'asset_added',
        'title': assetType.isNotEmpty
            ? 'notif_title_asset_type'.tr(namedArgs: {'type': assetType})
            : 'notif_title_asset'.tr(),
        'message': assetType.isNotEmpty
            ? 'notif_msg_asset_type'.tr(
                namedArgs: {'type': assetType, 'name': workerName},
              )
            : 'notif_msg_asset'.tr(namedArgs: {'name': workerName}),
        'data': {'name': workerName, 'type': assetType},
      });
    }
    return docRef.id;
  }

  Future<void> updateAsset(String id, Map<String, dynamic> data) async {
    Validators.validateAsset(data);
    final coll = _assets;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> deleteAsset(String id) async {
    final coll = _assets;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get assetsStream {
    final coll = _assets;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  
  Future<String> addHoliday(Map<String, dynamic> holiday) async {
    Validators.validateHoliday(holiday);
    final coll = _holidays;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...holiday,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (holiday['name'] ?? '').toString();
    if (name.isNotEmpty) {
      await addNotification({
        'type': 'holiday_added',
        'title': 'notif_title_holiday'.tr(namedArgs: {'name': name}),
        'message': 'notif_msg_holiday'.tr(namedArgs: {'name': name}),
        'data': {'name': name},
      });
    }
    return docRef.id;
  }

  Future<void> updateHoliday(String id, Map<String, dynamic> data) async {
    if (data.containsKey('name')) Validators.validateHoliday(data);
    final coll = _holidays;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> deleteHoliday(String id) async {
    final coll = _holidays;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get holidaysStream {
    final coll = _holidays;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> setCompanyWorkingDays(Iterable<int> weekdays) async {
    final coll = _holidays;
    if (coll == null) throw StateError('No authenticated user');
    final normalized =
        weekdays
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet()
            .toList()
          ..sort();
    if (normalized.isEmpty) {
      throw ArgumentError('At least one company working day is required');
    }
    await coll.doc('company_work_days').set({
      'type': 'company_work_days',
      'workingDays': normalized,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> seedDummyDataForUser({
    required String uid,
    required String displayName,
    required String email,
    bool force = false,
  }) async {
    final docRef = _db.collection('hrms_user').doc(uid);
    final userSnap = await docRef.get();

    if (!force && userSnap.exists) {
      final data = userSnap.data();
      if (data != null && data['hasDummyData'] == true) {
        return; 
      }
    }

    
    await docRef.set({
      'username': displayName,
      'email': email,
      'phone': '+1 (555) 019-2834',
      'businessName': 'Stark Industries',
      'companyId': 'STARK-999',
      'currency': 'USD',
      'contact1': '+1 (555) 019-2834',
      'contact2': '+1 (555) 019-5678',
      'address': '10880 Malibu Point, Malibu, CA',
      'hasDummyData': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    
    var batch = _db.batch();
    int count = 0;
    final workersColl = docRef.collection('hrms_workers');
    for (var w in DummyData.workers) {
      final copy = Map<String, dynamic>.from(w)..remove('id');
      batch.set(workersColl.doc(), {
        ...copy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }

    
    final attendanceColl = docRef.collection('hrms_attendance');
    for (var a in DummyData.attendance) {
      final copy = Map<String, dynamic>.from(a)..remove('id');
      batch.set(attendanceColl.doc(), {
        ...copy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }

    
    final expensesColl = docRef.collection('hrms_expenses');
    for (var e in DummyData.expenses) {
      final copy = Map<String, dynamic>.from(e)..remove('id');
      batch.set(expensesColl.doc(), {
        ...copy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }

    
    final payrollColl = docRef.collection('hrms_payroll');
    for (var p in DummyData.payroll) {
      final copy = Map<String, dynamic>.from(p)..remove('id');
      batch.set(payrollColl.doc(), {
        ...copy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }

    
    final timeoffColl = docRef.collection('hrms_timeoff');
    for (var t in DummyData.timeoff) {
      final copy = Map<String, dynamic>.from(t)..remove('id');
      batch.set(timeoffColl.doc(), {
        ...copy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }

    
    final holidaysColl = docRef.collection('hrms_holidays');
    for (var holidayList in DummyData.holidays.values) {
      for (var h in holidayList) {
        final copy = Map<String, dynamic>.from(h)..remove('id');
        batch.set(holidaysColl.doc(), {
          ...copy,
          'createdAt': FieldValue.serverTimestamp(),
        });
        count++;
        if (count % 500 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      }
    }

    
    final assetsColl = docRef.collection('hrms_assets');
    for (var a in DummyData.assets) {
      final copy = Map<String, dynamic>.from(a)..remove('id');
      batch.set(assetsColl.doc(), {
        ...copy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }

    if (count % 500 != 0) {
      await batch.commit();
    }
  }

  
  Future<void> addNotification(Map<String, dynamic> notification) async {
    final coll = _notifications;
    if (coll == null) return;
    await coll.add({
      ...notification,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> get notificationsStream {
    final coll = _notifications;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> markNotificationRead(String id) async {
    final coll = _notifications;
    if (coll == null) return;
    await coll.doc(id).update({'isRead': true});
  }

  Future<void> markAllNotificationsRead() async {
    final coll = _notifications;
    if (coll == null) return;
    final unread = await coll.where('isRead', isEqualTo: false).get();
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    if (unread.docs.isNotEmpty) {
      await batch.commit();
    }
  }

  Future<int> getUnreadNotificationCount() async {
    final coll = _notifications;
    if (coll == null) return 0;
    final unread = await coll.where('isRead', isEqualTo: false).get();
    return unread.docs.length;
  }

  Future<void> deleteNotification(String id) async {
    final coll = _notifications;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Future<void> clearAllNotifications() async {
    final coll = _notifications;
    if (coll == null) return;
    final snap = await coll.get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    if (snap.docs.isNotEmpty) {
      await batch.commit();
    }
  }
}
