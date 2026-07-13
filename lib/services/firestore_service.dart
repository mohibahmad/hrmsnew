import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_utils.dart';
import '../utils/validators.dart';
import 'auth_service.dart';
import 'dummy_data.dart';

class BulkWorkerResult {
  final int imported;
  final int skipped;
  BulkWorkerResult({required this.imported, required this.skipped});
}

class FirestoreService {
  static bool isTesting = false;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _userKey {
    final user = AuthService().currentUser;
    if (user == null) return '';

    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      return email.replaceAll('.', '_');
    }

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
    final user = AuthService().currentUser;
    if (user == null) return;

    final emailKey = email.trim().toLowerCase().replaceAll('.', '_');
    final doc = _db.collection('hrms_user').doc(emailKey);

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
    await doc.set(data, SetOptions(merge: true));
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
    final doc = await _db
        .collection('hrms_user')
        .doc(email.trim().toLowerCase())
        .get();
    if (!doc.exists) return false;
    return doc.data()?['isDeleted'] == true;
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

  /// Real-time stream of the user's profile document.
  /// Use this to react instantly to premium status changes.
  Stream<Map<String, dynamic>?> get userProfileStream {
    final doc = _userDoc;
    if (doc == null) return Stream.value(null);
    return doc.snapshots().map((snap) => snap.data() as Map<String, dynamic>?);
  }

  Future<String> addWorker(Map<String, dynamic> worker) async {
    Validators.validateWorker(worker);
    final coll = _workers;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...worker,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (worker['name'] ?? '').toString();
    if (name.isNotEmpty) {
      await addNotification({
        'type': 'worker_added',
        'title': 'Welcome $name, to the Team!',
        'message': '$name has been successfully added as a new team member.',
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

    for (var worker in workersList) {
      try {
        Validators.validateWorker(worker);
        final docRef = coll.doc();
        batch.set(docRef, {
          ...worker,
          'createdAt': FieldValue.serverTimestamp(),
        });
        count++;

        if (count % 500 == 0) {
          await batch.commit();
          batch = _db.batch();
        }
      } catch (e) {
        skipped++;
        continue;
      }
    }

    if (count % 500 != 0 && count > 0) {
      await batch.commit();
    }

    if (count > 0) {
      await addNotification({
        'type': 'worker_added',
        'title': 'Bulk Workers Added',
        'message': '$count workers have been successfully added via CSV import.',
      });
    }

    return BulkWorkerResult(imported: count, skipped: skipped);
  }

  Future<void> updateWorker(String id, Map<String, dynamic> data) async {
    Validators.validateWorker(data);
    final coll = _workers;
    if (coll == null) return;
    await coll.doc(id).update(data);
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
          ? 'New expense: $category'
          : 'New expense added',
      'message': amount.isNotEmpty
          ? 'An expense of \$$amount has been recorded.'
          : 'A new expense has been recorded.',
    });
    return docRef.id;
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    Validators.validateExpense(data);
    final coll = _expenses;
    if (coll == null) return;
    await coll.doc(id).update(data);
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
        'title': 'Attendance marked for $name',
        'message': 'Attendance has been recorded for $name.',
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

  /// Returns the total [absents] and [leaves] for a worker in the current
  /// calendar month, derived from the attendance records. Re-marks on the same
  /// day are de-duplicated so each day is only counted once.
  Future<Map<String, int>> getWorkerMonthlyAttendance(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    List<Map<String, dynamic>> records;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      records = List<Map<String, dynamic>>.from(DummyData.attendance);
    } else {
      final coll = _attendance;
      if (coll == null) return {'absents': 0, 'leaves': 0};

      // 🔥 FIX: Filter by month properly
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);

      final snap = await coll
          .where('email', isEqualTo: normalizedEmail)
          .where('createdAt', isGreaterThanOrEqualTo: startOfMonth)
          .where('createdAt', isLessThanOrEqualTo: endOfMonth)
          .get();

      records = snap.docs
          .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
          .toList();
    }

    int absents = 0;
    int leaves = 0;
    final seenDays = <String>{};
    for (final att in records) {
      final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
      if (normalizedEmail.isNotEmpty && attEmail != normalizedEmail) continue;
      final date = _dateFromCreatedAt(att['createdAt']);
      if (date == null) continue;
      if (date.year != DateTime.now().year ||
          date.month != DateTime.now().month)
        continue;
      final dayKey = '$attEmail-${date.year}-${date.month}-${date.day}';
      if (seenDays.contains(dayKey)) continue;
      seenDays.add(dayKey);
      final status = (att['status'] ?? '').toString();
      if (status == 'Absent') {
        absents++;
      } else if (status == 'Leave') {
        leaves++;
      }
    }
    return {'absents': absents, 'leaves': leaves};
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
        'title': 'Payroll processed for $name',
        'message': amount.isNotEmpty
            ? 'Salary of \$$amount has been processed for $name.'
            : 'Payroll has been recorded for $name.',
      });
    }
    return docRef.id;
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
        'title': 'Time Off assigned to $name',
        'message': '$type has been assigned to $name.',
      });
    }
    return docRef.id;
  }

  Future<void> updateTimeOffRecord(String id, Map<String, dynamic> data) async {
    final coll = _timeoff;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> deleteTimeOffRecord(String id) async {
    final coll = _timeoff;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get timeoffStream {
    final coll = _timeoff;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  // --- Assets CRUD ---
  Future<String> addAsset(Map<String, dynamic> asset) async {
    Validators.validateAsset(asset);
    final coll = _assets;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...asset,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final assetName = (asset['name'] ?? asset['assetName'] ?? '').toString();
    if (assetName.isNotEmpty) {
      await addNotification({
        'type': 'asset_added',
        'title': 'New asset added: $assetName',
        'message': '$assetName has been added to the company assets.',
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

  // --- Holidays CRUD ---
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
        'title': 'Holiday "$name" has been added',
        'message': '$name has been added to the holiday calendar.',
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
        return; // Already seeded
      }
    }

    // Create user profile
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
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));

    // Seed Workers
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

    // Seed Attendance
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

    // Seed Expenses
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

    // Seed Payroll
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

    // Seed Time Off requests
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

    // Seed Holidays
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

    // Seed Assets
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

  // ==================== NOTIFICATIONS ====================

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
