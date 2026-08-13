import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/date_time_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/validators.dart';
import '../utils/worker_identity.dart';
import 'auth_service.dart';
import 'attendance_service.dart';
import 'dummy_data.dart';
import 'error_reporter.dart';
import 'time_off_service.dart';
import 'upload_service.dart';
import 'preferences_service.dart';
import 'payroll_service.dart';

class BulkWorkerResult {
  final int imported;
  final int skipped;
  final List<String> skipReasons;

  final List<String> skippedClientRowIds;
  BulkWorkerResult({
    required this.imported,
    required this.skipped,
    this.skipReasons = const [],
    this.skippedClientRowIds = const [],
  });
}

class AttendanceLeaveSyncResult {
  final String attendanceId;
  final String timeOffId;
  const AttendanceLeaveSyncResult({
    required this.attendanceId,
    required this.timeOffId,
  });
}

class FirestoreService {
  static bool isTesting = false;
  static FirestoreService? _instance;
  static FirestoreService get instance => _instance!;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Set<String> _leaveNormalizationInFlight = <String>{};
  bool _holidaySchemaMigrationInFlight = false;

  FirestoreService() {
    _instance = this;
  }

  Map<String, dynamic> _withNormalizedCurrency(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized.containsKey('currency')) {
      normalized['currency'] = CurrencyUtils.normalize(normalized['currency']);
    }

    normalized.removeWhere((key, value) => value is num && !value.isFinite);
    return normalized;
  }

  Map<String, dynamic> _canonicalAssetReturnFields(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    final rawStatus = normalized['isReturned'];
    final rawReturnedDate = normalized['dateReturned'];
    final normalizedDateText = rawReturnedDate?.toString().trim().toLowerCase();

    final explicitStatus = rawStatus is bool
        ? rawStatus
        : switch (rawStatus?.toString().trim().toLowerCase()) {
            'true' || '1' || 'yes' => true,
            'false' || '0' || 'no' => false,
            _ => null,
          };
    final hasReturnedDate =
        rawReturnedDate != null &&
        normalizedDateText != null &&
        normalizedDateText.isNotEmpty &&
        normalizedDateText != 'in_use' &&
        normalizedDateText != '__in_use__';
    final returnedDate = hasReturnedDate
        ? AppDateUtils.dateFromValue(rawReturnedDate)
        : null;
    final isReturned =
        (explicitStatus ?? hasReturnedDate) && returnedDate != null;

    normalized['isReturned'] = isReturned;
    normalized['dateReturned'] = isReturned
        ? Timestamp.fromDate(
            DateTime(returnedDate.year, returnedDate.month, returnedDate.day),
          )
        : null;
    return normalized;
  }

  Map<String, dynamic> _canonicalHolidayFields(
    Map<String, dynamic> data, {
    required bool forUpdate,
  }) {
    final normalized = Map<String, dynamic>.from(data);
    final touchesDate = const [
      'date',
      'holidayDate',
      'day',
      'month',
      'year',
    ].any(normalized.containsKey);
    if (touchesDate) {
      final date = AppDateUtils.holidayRecordDate(
        normalized,
        fallbackYear: DateTime.now().year,
      );
      if (date != null) {
        normalized['date'] = Timestamp.fromDate(
          DateTime(date.year, date.month, date.day),
        );
      }
    }

    for (final key in [
      'dayOfWeek',
      'remainingDays',
      if (touchesDate) ...['holidayDate', 'day', 'month', 'year'],
    ]) {
      if (forUpdate) {
        normalized[key] = FieldValue.delete();
      } else {
        normalized.remove(key);
      }
    }
    return normalized;
  }

  Future<void> _migrateHolidaySchema(QuerySnapshot snapshot) async {
    if (_holidaySchemaMigrationInFlight) return;
    final migrations = <DocumentReference, Map<String, dynamic>>{};
    for (final document in snapshot.docs) {
      final raw = document.data();
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      if (data['type'] == 'company_work_days') continue;
      final hasLegacyFields = const [
        'holidayDate',
        'day',
        'month',
        'year',
        'dayOfWeek',
        'remainingDays',
      ].any(data.containsKey);
      final hasCanonicalTimestamp = data['date'] is Timestamp;
      if (!hasLegacyFields && hasCanonicalTimestamp) continue;

      final date = AppDateUtils.holidayRecordDate(
        data,
        fallbackYear: DateTime.now().year,
      );
      final update = <String, dynamic>{
        'holidayDate': FieldValue.delete(),
        'day': FieldValue.delete(),
        'month': FieldValue.delete(),
        'year': FieldValue.delete(),
        'dayOfWeek': FieldValue.delete(),
        'remainingDays': FieldValue.delete(),
      };
      if (date != null) {
        update['date'] = Timestamp.fromDate(
          DateTime(date.year, date.month, date.day),
        );
      }
      migrations[document.reference] = update;
    }
    if (migrations.isEmpty) return;

    _holidaySchemaMigrationInFlight = true;
    try {
      var batch = _db.batch();
      var writes = 0;
      for (final entry in migrations.entries) {
        batch.update(entry.key, entry.value);
        writes++;
        if (writes == 450) {
          await batch.commit();
          batch = _db.batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
    } finally {
      _holidaySchemaMigrationInFlight = false;
    }
  }

  String _safeDocumentKey(String value) => value.trim().replaceAll('/', '_');

  String _payrollDocumentId(String payrollKey) => _safeDocumentKey(payrollKey);

  String _payrollExpenseDocumentId(String payrollKey) =>
      'salary_${_safeDocumentKey(payrollKey)}';

  String _payrollNotificationDocumentId(String payrollKey) =>
      _safeDocumentKey('payroll_${payrollKey.trim()}');

  String _attendanceDocumentId(String workerId, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final dateKey =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return '${workerId}_$dateKey';
  }

  Future<({DocumentReference reference, bool alreadyExistsForDate})>
  _attendanceCreateTarget(
    CollectionReference attendanceCollection,
    String workerId,
    DateTime requestedDate,
  ) async {
    final deterministicReference = attendanceCollection.doc(
      _attendanceDocumentId(workerId, requestedDate),
    );
    final existingSnapshot = await deterministicReference.get();
    if (!existingSnapshot.exists) {
      return (reference: deterministicReference, alreadyExistsForDate: false);
    }

    final existingData = existingSnapshot.data();
    if (existingData is Map) {
      final record = Map<String, dynamic>.from(existingData);
      if (AttendanceService.isRecordForDate(record, requestedDate)) {
        return (reference: deterministicReference, alreadyExistsForDate: true);
      }
    }

    return (reference: attendanceCollection.doc(), alreadyExistsForDate: false);
  }

  String _timeOffDateKey(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteDocumentsInChunks(
    Iterable<DocumentReference> references,
  ) async {
    var batch = _db.batch();
    var pending = 0;

    for (final reference in references) {
      batch.delete(reference);
      pending++;
      if (pending == 450) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    if (pending > 0) {
      await batch.commit();
    }
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
      'currency': CurrencyUtils.defaultCode,
      'hasDummyData': false,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    final doc = _userDoc;
    if (doc == null) return;
    final normalized = _withNormalizedCurrency(data);
    if (normalized['isDeleted'] == false) {
      normalized['deletedAt'] = FieldValue.delete();
    }
    await doc.set(normalized, SetOptions(merge: true));
  }

  Future<void> deleteUserData() async {
    final doc = _userDoc;
    if (doc == null) return;
    await doc.set({'isDeleted': true}, SetOptions(merge: true));
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
      final snapshot = await doc
          .collection(collectionName)
          .where('isDummyData', isEqualTo: true)
          .get();
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

  Future<Map<String, dynamic>?> getUserProfileOrThrow() async {
    if (isTesting) return {'isPremium': false, 'hasDummyData': false};
    final doc = _userDoc;
    if (doc == null) return null;
    final snapshot = await doc.get();
    return snapshot.data() as Map<String, dynamic>?;
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
      try {
        await addNotification({
          'type': 'worker_added',
          'title': 'notif_title_new_member'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_new_member'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'WorkerNotification');
      }
    }
    return docRef.id;
  }

  Future<BulkWorkerResult> addBulkWorkers(
    List<Map<String, dynamic>> workersList,
  ) async {
    final coll = _workers;
    if (coll == null) {
      return BulkWorkerResult(imported: 0, skipped: workersList.length);
    }

    final existingSnapshot = await coll.get();
    final existingEmails = <String>{};
    final existingNationalIds = <String>{};
    for (final doc in existingSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final e = WorkerIdentity.normalizeEmail(data['email']);
      if (e.isNotEmpty) existingEmails.add(e);
      final n = WorkerIdentity.normalizeNationalId(data['nationalId']);
      if (n.isNotEmpty) existingNationalIds.add(n);
    }

    final acceptedWorkers = <Map<String, dynamic>>[];
    final validWorkers = <Map<String, dynamic>>[];
    final skipReasons = <String>[];
    final skippedClientRowIds = <String>[];
    int skipped = 0;

    for (var worker in workersList) {
      final clientRowId =
          (worker['clientRowId'] ?? worker['client_row_id'] ?? '')
              .toString()
              .trim();
      try {
        Validators.validateWorker(worker);
        final email = WorkerIdentity.normalizeEmail(worker['email']);
        final nationalId = WorkerIdentity.normalizeNationalId(
          worker['nationalId'],
        );

        String? dupField;
        if (email.isNotEmpty && existingEmails.contains(email)) {
          dupField = 'Email';
        } else if (nationalId.isNotEmpty &&
            existingNationalIds.contains(nationalId)) {
          dupField = 'Government ID';
        }

        if (dupField != null) {
          skipped++;
          if (clientRowId.isNotEmpty) skippedClientRowIds.add(clientRowId);
          skipReasons.add(
            'Duplicate $dupField: ${worker['name'] ?? worker['email'] ?? ''}',
          );
          continue;
        }

        if (email.isNotEmpty) existingEmails.add(email);
        if (nationalId.isNotEmpty) existingNationalIds.add(nationalId);

        acceptedWorkers.add(worker);
        validWorkers.add(worker);
      } catch (e) {
        skipped++;
        if (clientRowId.isNotEmpty) skippedClientRowIds.add(clientRowId);
        skipReasons.add('Validation error: ${e.toString()}');
        continue;
      }
    }

    int count = 0;
    if (validWorkers.isNotEmpty) {
      const batchSize = 100;
      final batches = <Future<void>>[];
      for (var i = 0; i < validWorkers.length; i += batchSize) {
        final chunk = validWorkers.sublist(
          i,
          (i + batchSize).clamp(0, validWorkers.length),
        );
        batches.add(_commitBatch(coll, chunk));
      }
      await Future.wait(batches);
      count = validWorkers.length;
    }

    if (count > 0) {
      try {
        await addNotification({
          'type': 'worker_added',
          'title': 'notif_title_bulk_workers'.tr(),
          'message': 'notif_msg_bulk_workers'.tr(
            namedArgs: {'count': '$count'},
          ),
          'data': {'count': '$count'},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'BulkWorkerNotification',
        );
      }
    }

    return BulkWorkerResult(
      imported: count,
      skipped: skipped,
      skipReasons: skipReasons,
      skippedClientRowIds: skippedClientRowIds,
    );
  }

  Future<void> _commitBatch(
    CollectionReference coll,
    List<Map<String, dynamic>> workers,
  ) async {
    final batch = _db.batch();
    for (final worker in workers) {
      final docRef = coll.doc();
      final canonicalWorker = {
        ...worker,
        ...TimeOffService.canonicalWorkerLeaveFields(worker),
      };
      batch.set(docRef, {
        ..._withNormalizedCurrency(canonicalWorker),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> updateWorker(String id, Map<String, dynamic> data) async {
    Validators.validateWorker(data);
    final coll = _workers;
    if (coll == null) return;
    final existingSnapshot = await coll.get();
    final existingWorkers = existingSnapshot.docs.map(
      (doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id},
    );
    final duplicateField = WorkerIdentity.duplicateField(
      data,
      existingWorkers,
      excludeId: id,
    );
    if (duplicateField != null) {
      throw DuplicateWorkerException(duplicateField);
    }
    final currentWorker = existingWorkers.firstWhere(
      (worker) => worker['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    if (currentWorker.isNotEmpty) {
      final normalizedName = WorkerIdentity.normalizeName(
        currentWorker['name'],
      );
      final sameNameWorkers = existingWorkers.where(
        (worker) =>
            WorkerIdentity.normalizeName(worker['name']) == normalizedName,
      );
      await _backfillLegacyWorkerReferences(
        workerId: id,
        previousWorker: currentWorker,
        allowNameFallback:
            normalizedName.isNotEmpty && sameNameWorkers.length == 1,
      );
    }
    final workerUpdate = <String, dynamic>{...currentWorker, ...data};
    final timeOffSnapshot = await _timeoff?.get();
    final timeOffRecords =
        timeOffSnapshot?.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList() ??
        const <Map<String, dynamic>>[];
    final workerWithId = {...workerUpdate, 'id': id, 'workerId': id};
    final assignedByType = TimeOffService.paidDaysUsedForWorkerByType(
      workerWithId,
      timeOffRecords,
    );
    for (final type in const [
      'Annual Leave',
      'Sick Leave',
      'Casual Leave',
      'Medical Leave',
    ]) {
      final assigned = assignedByType[type] ?? 0;
      final configured = TimeOffService.configuredLimitForType(
        workerWithId,
        type,
      );
      if (configured < assigned) {
        throw StateError(
          '$assigned $type days are already assigned. '
          'The allowance cannot be set below $assigned.',
        );
      }
    }
    final remainingBalances =
        TimeOffService.remainingBalancesFromAssignedRecords(
          workerWithId,
          timeOffRecords,
        );
    await coll.doc(id).update({
      ..._withNormalizedCurrency(data),
      ...TimeOffService.canonicalWorkerLeaveFields(
        workerUpdate,
        remainingBalances: remainingBalances,
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _backfillLegacyWorkerReferences({
    required String workerId,
    required Map<String, dynamic> previousWorker,
    required bool allowNameFallback,
  }) async {
    final previousEmail = WorkerIdentity.normalizeEmail(
      previousWorker['email'],
    );
    final previousName = WorkerIdentity.normalizeName(previousWorker['name']);
    if (previousEmail.isEmpty && (!allowNameFallback || previousName.isEmpty)) {
      return;
    }

    final collections = <CollectionReference?>[
      _attendance,
      _timeoff,
      _payroll,
      _assets,
    ];
    var batch = _db.batch();
    var pendingWrites = 0;

    for (final collection in collections) {
      if (collection == null) continue;
      final snapshot = await collection.get();
      for (final document in snapshot.docs) {
        final record = document.data() as Map<String, dynamic>;
        if ((record['workerId'] ?? '').toString().trim().isNotEmpty) continue;

        final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
        final recordName = WorkerIdentity.normalizeName(
          record['name'] ?? record['workerName'],
        );
        final matchesEmail =
            previousEmail.isNotEmpty && recordEmail == previousEmail;
        final matchesUniqueName =
            previousEmail.isEmpty &&
            allowNameFallback &&
            previousName.isNotEmpty &&
            recordName == previousName;
        if (!matchesEmail && !matchesUniqueName) continue;

        batch.update(document.reference, {'workerId': workerId});
        pendingWrites++;
        if (pendingWrites == 450) {
          await batch.commit();
          batch = _db.batch();
          pendingWrites = 0;
        }
      }
    }
    if (pendingWrites > 0) await batch.commit();
  }

  Future<void> updateWorkerLeaves(
    String id,
    Map<String, dynamic> leaveData,
  ) async {
    final coll = _workers;
    if (coll == null || id.isEmpty) return;
    final workerRef = coll.doc(id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(workerRef);
      if (!snapshot.exists) throw StateError('Worker does not exist');
      final current = (snapshot.data() as Map<String, dynamic>?) ?? {};
      final merged = <String, dynamic>{...current, ...leaveData};
      transaction.update(workerRef, {
        ...leaveData,
        ...TimeOffService.canonicalWorkerLeaveFields(merged),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> normalizeWorkerLeaveSchemaIfNeeded(
    String id,
    Map<String, dynamic> worker,
  ) async {
    final coll = _workers;
    if (coll == null || id.isEmpty) return;
    final timeOffSnapshot = await _timeoff?.get();
    final timeOffRecords =
        timeOffSnapshot?.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList() ??
        const <Map<String, dynamic>>[];
    final workerWithId = {...worker, 'id': id, 'workerId': id};
    final remainingBalances =
        TimeOffService.remainingBalancesFromAssignedRecords(
          workerWithId,
          timeOffRecords,
        );
    final canonical = TimeOffService.canonicalWorkerLeaveFields(
      workerWithId,
      remainingBalances: remainingBalances,
    );
    if (TimeOffService.hasCanonicalWorkerLeaveFields({
      ...worker,
      ...canonical,
    })) {
      final currentBalances = worker['leaveBalances'] is Map
          ? Map<String, dynamic>.from(worker['leaveBalances'] as Map)
          : const <String, dynamic>{};
      final expectedBalances = canonical['leaveBalances'] as Map;
      final balancesMatch = expectedBalances.entries.every(
        (entry) => currentBalances[entry.key] == entry.value,
      );
      if (balancesMatch) return;
    }
    await coll.doc(id).update({
      ...canonical,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateWorkerFields(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final coll = _workers;
    if (coll == null || id.isEmpty) return;
    await coll.doc(id).set({
      ..._withNormalizedCurrency(fields),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<int> applyLeavePolicyToWorkers({
    required List<Map<String, dynamic>> workers,
    required int annualLeaveDays,
    required int sickLeaveDays,
    required int casualLeaveDays,
    required int medicalLeaveDays,
    required String policyName,
    required List<Map<String, dynamic>> timeOffRecords,
  }) async {
    final coll = _workers;
    if (coll == null) return 0;

    final recordsByWorkerId = <String, List<Map<String, dynamic>>>{};
    final legacyRecordsByEmail = <String, List<Map<String, dynamic>>>{};
    for (final record in timeOffRecords) {
      if (!TimeOffService.isActiveRecord(record)) continue;
      final workerId = (record['workerId'] ?? '').toString().trim();
      final email = (record['email'] ?? '').toString().trim().toLowerCase();
      if (workerId.isNotEmpty) {
        recordsByWorkerId.putIfAbsent(workerId, () => []).add(record);
      } else if (email.isNotEmpty) {
        legacyRecordsByEmail.putIfAbsent(email, () => []).add(record);
      }
    }

    var updated = 0;
    var batch = _db.batch();
    var pending = 0;

    for (final worker in workers) {
      final workerId = (worker['id'] ?? '').toString().trim();
      final workerEmail = (worker['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final workerRecords = workerId.isNotEmpty
          ? (recordsByWorkerId[workerId] ?? const <Map<String, dynamic>>[])
          : (legacyRecordsByEmail[workerEmail] ??
                const <Map<String, dynamic>>[]);

      final workerWithPolicy = <String, dynamic>{
        ...worker,
        'annualLeaves': annualLeaveDays,
        'sickLeaves': sickLeaveDays,
        'casualLeaves': casualLeaveDays,
        'medicalLeaves': medicalLeaveDays,
      };
      final balances = TimeOffService.remainingBalancesFromAssignedRecords(
        workerWithPolicy,
        workerRecords,
      );
      batch.update(coll.doc(workerId), {
        ...TimeOffService.canonicalWorkerLeaveFields(
          workerWithPolicy,
          remainingBalances: balances,
        ),
        'leavePolicy': policyName,
      });
      pending++;
      updated++;

      if (pending == 450) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    if (pending > 0) {
      await batch.commit();
    }

    return updated;
  }

  Future<int> applyGenericPolicyToWorkers({
    required String policyType,
    required Map<String, dynamic> policyData,
    required List<Map<String, dynamic>> workers,
    required String appliedToWorkerId,
  }) async {
    final coll = _workers;
    if (coll == null) return 0;
    final policyTimeOffSnapshot = policyType == 'Leave Policy'
        ? await _timeoff?.get()
        : null;
    final policyTimeOffRecords =
        policyTimeOffSnapshot?.docs
            .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
            .toList() ??
        const <Map<String, dynamic>>[];

    var updated = 0;
    var batch = _db.batch();
    var pending = 0;

    for (final worker in workers) {
      final workerId = (worker['id'] ?? '').toString().trim();
      if (workerId.isEmpty) continue;

      final selectedWorkerIds = appliedToWorkerId
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (appliedToWorkerId != 'all' && !selectedWorkerIds.contains(workerId)) {
        continue;
      }

      final updates = <String, dynamic>{};
      final policyName = policyData['policyName'] ?? policyType;

      if (policyType == 'Leave Policy') {
        final annual =
            int.tryParse(policyData['annualLeaveDays']?.toString() ?? '14') ??
            14;
        final sick =
            int.tryParse(policyData['sickLeaves']?.toString() ?? '5') ?? 5;
        final casual =
            int.tryParse(policyData['casualLeaves']?.toString() ?? '5') ?? 5;
        final medical =
            int.tryParse(policyData['medicalLeaves']?.toString() ?? '5') ?? 5;
        updates['annualLeaves'] = annual;
        updates['sickLeaves'] = sick;
        updates['casualLeaves'] = casual;
        updates['medicalLeaves'] = medical;
        updates['leavePolicy'] = policyName;
        final workerWithPolicy = {...worker, ...updates, 'workerId': workerId};
        updates.addAll(
          TimeOffService.canonicalWorkerLeaveFields(
            workerWithPolicy,
            remainingBalances:
                TimeOffService.remainingBalancesFromAssignedRecords(
                  workerWithPolicy,
                  policyTimeOffRecords,
                ),
          ),
        );
      } else if (policyType == 'Payroll Policy') {
        updates['paymentFrequency'] =
            policyData['paymentFrequency'] ?? 'Monthly';
        updates['taxRatePercent'] =
            double.tryParse(
              policyData['taxRatePercent']?.toString() ?? '5.0',
            ) ??
            5.0;
        updates['payrollPolicy'] = policyName;
      } else if (policyType == 'Holiday Policy') {
        updates['weeklyOffDays'] = policyData['weeklyOffDays'] ?? 'Sunday';
        updates['paidHolidaysCount'] =
            int.tryParse(policyData['paidHolidaysCount']?.toString() ?? '10') ??
            10;
        updates['holidayPolicy'] = policyName;
      } else if (policyType == 'Asset Policy') {
        updates['maxAssetsPerWorker'] =
            int.tryParse(policyData['maxAssetsPerWorker']?.toString() ?? '3') ??
            3;
        updates['returnGracePeriodDays'] =
            int.tryParse(
              policyData['returnGracePeriodDays']?.toString() ?? '7',
            ) ??
            7;
        updates['assetPolicy'] = policyName;
      }

      if (updates.isNotEmpty) {
        batch.update(coll.doc(workerId), updates);
        pending++;
        updated++;
      }

      if (pending == 450) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    if (pending > 0) {
      await batch.commit();
    }

    return updated;
  }

  Future<List<Map<String, dynamic>>> getTimeoffOnce() async {
    final coll = _timeoff;
    if (coll == null) return const [];
    final snapshot = await coll.get();
    return snapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();
  }

  Future<void> deleteWorker(String id) async {
    final workersColl = _workers;
    if (workersColl == null || id.trim().isEmpty) return;

    final workerId = id.trim();

    final workerDoc = await workersColl.doc(workerId).get();
    final workerData = workerDoc.data() as Map<String, dynamic>?;
    final mediaUrls = <String>{};
    if (workerData != null) {
      for (final key in ['profileImage', 'frontId', 'backId', 'cv']) {
        final url = (workerData[key] ?? '').toString().trim();
        if (url.isNotEmpty) mediaUrls.add(url);
      }
    }

    final payrollColl = _payroll;
    final expensesColl = _expenses;
    final notificationsColl = _notifications;

    final payrollKeys = <String>{};
    if (payrollColl != null) {
      final payrollSnapshot = await payrollColl
          .where('workerId', isEqualTo: workerId)
          .get();

      for (final document in payrollSnapshot.docs) {
        final data = document.data() as Map<String, dynamic>;
        final payrollKey = (data['payrollKey'] ?? '').toString().trim();
        if (payrollKey.isNotEmpty) payrollKeys.add(payrollKey);
      }
    }

    final referencesToDelete = <DocumentReference>[];

    for (final collection in <CollectionReference?>[
      _attendance,
      _timeoff,
      _payroll,
      _expenses,
      _assets,
    ]) {
      if (collection == null) continue;
      final snapshot = await collection
          .where('workerId', isEqualTo: workerId)
          .get();
      referencesToDelete.addAll(snapshot.docs.map((doc) => doc.reference));
    }

    for (final payrollKey in payrollKeys) {
      if (expensesColl != null) {
        final salaryExpenses = await expensesColl
            .where('payrollKey', isEqualTo: payrollKey)
            .get();
        referencesToDelete.addAll(
          salaryExpenses.docs.map((doc) => doc.reference),
        );
      }

      if (notificationsColl != null) {
        referencesToDelete.add(
          notificationsColl.doc(_payrollNotificationDocumentId(payrollKey)),
        );
      }
    }

    final uniqueReferences = <String, DocumentReference>{};
    for (final reference in referencesToDelete) {
      uniqueReferences[reference.path] = reference;
    }

    await _deleteDocumentsInChunks(uniqueReferences.values);
    await workersColl.doc(workerId).delete();

    for (final url in mediaUrls) {
      try {
        await UploadService.deleteByUrl(url);
      } catch (_) {}
    }
  }

  Stream<QuerySnapshot> get workersStream {
    final coll = _workers;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      for (final document in snapshot.docs) {
        final worker = document.data() as Map<String, dynamic>;
        if (TimeOffService.hasCanonicalWorkerLeaveFields(worker) ||
            !_leaveNormalizationInFlight.add(document.id)) {
          continue;
        }
        unawaited(
          normalizeWorkerLeaveSchemaIfNeeded(document.id, worker)
              .catchError((Object error, StackTrace stackTrace) {
                ErrorReporter.report(
                  error,
                  stackTrace,
                  context: 'NormalizeWorkerLeaveSchema',
                );
              })
              .whenComplete(
                () => _leaveNormalizationInFlight.remove(document.id),
              ),
        );
      }
      return snapshot;
    });
  }

  Future<QuerySnapshot> getWorkersOnce() async {
    final coll = _workers;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.get();
  }

  Future<DuplicateWorkerField?> findDuplicateWorkerField({
    required String? email,
    required String? nationalId,
    String? excludeId,
  }) async {
    final coll = _workers;
    if (coll == null) throw StateError('No authenticated user');

    final snapshot = await coll.get();
    final existingWorkers = snapshot.docs.map(
      (doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id},
    );
    return WorkerIdentity.duplicateField(
      <String, dynamic>{
        'email': ?email,
        'nationalId': ?nationalId,
      },
      existingWorkers,
      excludeId: excludeId,
    );
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
    try {
      await addNotification({
        'type': 'expense_added',
        'title': category.isNotEmpty
            ? 'notif_title_expense_category'.tr(
                namedArgs: {'category': category},
              )
            : 'notif_title_expense'.tr(),
        'message': amount.isNotEmpty
            ? 'notif_msg_expense_amount'.tr(
                namedArgs: {
                  'amount':
                      '${CurrencyUtils.symbolFor(PreferencesService.cachedCompanyCurrency)}$amount',
                },
              )
            : 'notif_msg_expense'.tr(),
        'data': {
          'category': category,
          'amount': amount.isNotEmpty
              ? '${CurrencyUtils.symbolFor(PreferencesService.cachedCompanyCurrency)}$amount'
              : '',
        },
      });
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'ExpenseNotification');
    }
    return docRef.id;
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    Validators.validateExpense(data);
    final coll = _expenses;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> updatePayrollLinkedExpense({
    required String expenseId,
    required String payrollKey,
    required Map<String, dynamic> expenseData,
    required double netAmount,
    required String currency,
  }) async {
    Validators.validateExpense(expenseData);
    final expensesColl = _expenses;
    final payrollColl = _payroll;
    final normalizedKey = payrollKey.trim();
    if (expensesColl == null || payrollColl == null) {
      throw StateError('No authenticated user');
    }
    if (expenseId.trim().isEmpty || normalizedKey.isEmpty) {
      throw ArgumentError('Expense id and payroll key are required');
    }

    final payrollDocs = await payrollColl
        .where('payrollKey', isEqualTo: normalizedKey)
        .get();
    final batch = _db.batch();
    batch.update(expensesColl.doc(expenseId.trim()), {
      ...expenseData,
      'amount': netAmount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final salaryUpdates = PayrollService.editedNetSalaryFields(
      netAmount,
      currency: currency,
    );
    for (final payroll in payrollDocs.docs) {
      batch.update(payroll.reference, {
        ...salaryUpdates,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastModified': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> upsertPayrollExpense(
    Map<String, dynamic> expense, {
    required String payrollKey,
  }) async {
    Validators.validateExpense(expense);
    final coll = _expenses;
    if (coll == null) throw StateError('No authenticated user');

    final normalizedPayrollKey = payrollKey.trim();
    if (normalizedPayrollKey.isEmpty) {
      throw ArgumentError('payrollKey is required for a payroll expense');
    }

    final targetRef = coll.doc(_payrollExpenseDocumentId(normalizedPayrollKey));
    final existing = await coll
        .where('payrollKey', isEqualTo: normalizedPayrollKey)
        .get();
    final targetSnapshot = await targetRef.get();

    final batch = _db.batch();
    batch.set(targetRef, {
      ...expense,
      'payrollKey': normalizedPayrollKey,
      if (!targetSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (final document in existing.docs) {
      if (document.reference.path != targetRef.path) {
        batch.delete(document.reference);
      }
    }

    await batch.commit();
  }

  Future<void> upsertBulkPayrollExpenses(
    List<Map<String, dynamic>> expenses,
  ) async {
    final coll = _expenses;
    if (coll == null) throw StateError('No authenticated user');
    if (expenses.isEmpty) return;

    const chunkSize = 450;
    for (var start = 0; start < expenses.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, expenses.length).toInt();
      final batch = _db.batch();
      for (final expense in expenses.sublist(start, end)) {
        Validators.validateExpense(expense);
        final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
        if (payrollKey.isEmpty) {
          throw ArgumentError('payrollKey is required for a payroll expense');
        }
        final docRef = coll.doc(_payrollExpenseDocumentId(payrollKey));
        batch.set(docRef, {
          ...expense,
          'payrollKey': payrollKey,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> deleteExpense(String id) async {
    final coll = _expenses;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Future<void> deletePayrollLinkedExpense({
    required String expenseId,
    required String payrollKey,
  }) async {
    final expensesColl = _expenses;
    final payrollColl = _payroll;
    final normalizedKey = payrollKey.trim();
    if (expensesColl == null || payrollColl == null) {
      throw StateError('No authenticated user');
    }
    if (expenseId.trim().isEmpty || normalizedKey.isEmpty) {
      throw ArgumentError('Expense id and payroll key are required');
    }

    final payrollDocs = await payrollColl
        .where('payrollKey', isEqualTo: normalizedKey)
        .get();
    final batch = _db.batch();
    batch.delete(expensesColl.doc(expenseId.trim()));
    for (final payroll in payrollDocs.docs) {
      batch.update(payroll.reference, {
        ...PayrollService.reopenedPayrollFields(),
        'paidAt': FieldValue.delete(),
        'paidOn': FieldValue.delete(),
        'paymentDate': FieldValue.delete(),
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastModified': FieldValue.serverTimestamp(),
      });
    }
    if (_notifications != null) {
      batch.delete(
        _notifications!.doc(_payrollNotificationDocumentId(normalizedKey)),
      );
    }
    await batch.commit();
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
    final workerId = (record['workerId'] ?? '').toString().trim();
    final attendanceDate = AppDateUtils.dateFromValue(
      record['attendanceDate'] ?? record['date'],
    );
    final now = attendanceDate ?? DateTime.now();
    var createsDocument = true;
    DocumentReference docRef;
    if (workerId.isNotEmpty) {
      final target = await _attendanceCreateTarget(coll, workerId, now);
      docRef = target.reference;
      createsDocument = !target.alreadyExistsForDate;
    } else {
      docRef = coll.doc();
    }
    await docRef.set({
      ...record,
      'attendanceDate': Timestamp.fromDate(
        DateTime(now.year, now.month, now.day),
      ),
      if (createsDocument) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final name = (record['name'] ?? record['workerName'] ?? '').toString();
    if (name.isNotEmpty) {
      try {
        await addNotification({
          'type': 'attendance_marked',
          'title': 'notif_title_attendance'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_attendance'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'AttendanceNotification',
        );
      }
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
    final attendanceDate = AppDateUtils.dateFromValue(
      data['attendanceDate'] ?? data['date'],
    );
    final dateToUpdate = attendanceDate ?? DateTime.now();
    await coll.doc(id).update({
      ...data,
      'attendanceDate': Timestamp.fromDate(
        DateTime(dateToUpdate.year, dateToUpdate.month, dateToUpdate.day),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAttendanceRecord(String id) async {
    final coll = _attendance;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Future<AttendanceLeaveSyncResult> saveAttendanceWithLeaveSync({
    required Map<String, dynamic> attendanceRecord,
    String? attendanceId,
    String? timeOffId,
    Map<String, dynamic>? timeOffRecord,
    Map<String, dynamic>? remainingTimeOffRecord,
    bool createNewTimeOff = false,
    bool deleteTimeOff = false,
    String? workerId,
    Map<String, dynamic>? balance,
  }) async {
    Validators.validateAttendance(attendanceRecord);
    if (timeOffRecord != null) Validators.validateTimeOff(timeOffRecord);
    if (remainingTimeOffRecord != null) {
      Validators.validateTimeOff(remainingTimeOffRecord);
    }
    final attendanceColl = _attendance;
    final workersColl = _workers;
    if (attendanceColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }

    final batch = _db.batch();

    final attendanceDate = AppDateUtils.dateFromValue(
      attendanceRecord['attendanceDate'] ?? attendanceRecord['date'],
    );
    final now = attendanceDate ?? DateTime.now();
    final normalizedWorkerId = (workerId ?? '').trim();

    final callerHasNoAttendanceId =
        attendanceId == null || attendanceId.trim().isEmpty;
    if (callerHasNoAttendanceId && normalizedWorkerId.isEmpty) {
      throw ArgumentError(
        'workerId is required when creating a new attendance record '
        'to ensure a deterministic document ID.',
      );
    }
    late final DocumentReference attendanceRef;
    var createsAttendanceDocument = false;
    if (callerHasNoAttendanceId) {
      final target = await _attendanceCreateTarget(
        attendanceColl,
        normalizedWorkerId,
        now,
      );
      attendanceRef = target.reference;
      createsAttendanceDocument = !target.alreadyExistsForDate;
    } else {
      attendanceRef = attendanceColl.doc(attendanceId.trim());
    }

    final timeOffColl = _timeoff;
    final existingTimeOffId = (timeOffId ?? '').trim();
    String savedTimeOffId = existingTimeOffId;
    final workerUpdate = <String, dynamic>{...?balance};
    Map<String, dynamic>? dateLocks;
    final changesTimeOff =
        timeOffRecord != null ||
        remainingTimeOffRecord != null ||
        (deleteTimeOff && existingTimeOffId.isNotEmpty);
    if (normalizedWorkerId.isNotEmpty && changesTimeOff) {
      final workerSnapshot = await workersColl.doc(normalizedWorkerId).get();
      final workerData = workerSnapshot.data() as Map<String, dynamic>?;
      dateLocks = workerData?['timeOffDateLocks'] is Map
          ? Map<String, dynamic>.from(workerData!['timeOffDateLocks'] as Map)
          : <String, dynamic>{};
    }
    if (timeOffColl != null && changesTimeOff) {
      if (remainingTimeOffRecord != null) {
        if (existingTimeOffId.isEmpty) {
          throw ArgumentError(
            'timeOffId is required when retaining dates from a Time Off record',
          );
        }
        batch.set(timeOffColl.doc(existingTimeOffId), {
          ...remainingTimeOffRecord,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (timeOffRecord != null) {
        final isNewTimeOff = existingTimeOffId.isEmpty || createNewTimeOff;
        final timeOffRef = isNewTimeOff
            ? timeOffColl.doc()
            : timeOffColl.doc(existingTimeOffId);
        batch.set(timeOffRef, {
          ...timeOffRecord,
          if (isNewTimeOff) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        savedTimeOffId = timeOffRef.id;
        if (dateLocks != null) {
          final dateKey = _timeOffDateKey(now);
          final owner = (dateLocks[dateKey] ?? '').toString().trim();
          final transfersExistingLock =
              createNewTimeOff && owner == existingTimeOffId;
          if (owner.isNotEmpty &&
              owner != savedTimeOffId &&
              !transfersExistingLock) {
            throw const DuplicateTimeOffDateException();
          }
          dateLocks[dateKey] = savedTimeOffId;
        }
      } else if (deleteTimeOff) {
        batch.delete(timeOffColl.doc(existingTimeOffId));
        if (dateLocks != null) {
          final dateKey = _timeOffDateKey(now);
          if ((dateLocks[dateKey] ?? '').toString() == existingTimeOffId) {
            dateLocks.remove(dateKey);
          }
        }
      } else if (remainingTimeOffRecord != null && dateLocks != null) {
        final dateKey = _timeOffDateKey(now);
        if ((dateLocks[dateKey] ?? '').toString() == existingTimeOffId) {
          dateLocks.remove(dateKey);
        }
      }
    }

    batch.set(attendanceRef, {
      ...attendanceRecord,
      if (timeOffRecord != null) 'timeOffId': savedTimeOffId,
      // Always normalize the record date. Legacy attendance documents may
      // have no `attendanceDate` (or a string value), which makes monthly
      // payroll queries miss them after an edit.
      'attendanceDate': Timestamp.fromDate(
        DateTime(now.year, now.month, now.day),
      ),
      if (createsAttendanceDocument) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (dateLocks != null) workerUpdate['timeOffDateLocks'] = dateLocks;
    if (normalizedWorkerId.isNotEmpty && workerUpdate.isNotEmpty) {
      batch.set(
        workersColl.doc(normalizedWorkerId),
        workerUpdate,
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    final name =
        (attendanceRecord['name'] ?? attendanceRecord['workerName'] ?? '')
            .toString();
    if (name.isNotEmpty) {
      try {
        await addNotification({
          'type': 'attendance_marked',
          'title': 'notif_title_attendance'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_attendance'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'attendanceLeaveNotification',
        );
      }
    }

    return AttendanceLeaveSyncResult(
      attendanceId: attendanceRef.id,
      timeOffId: savedTimeOffId,
    );
  }

  Future<List<Map<String, dynamic>>> getMonthlyAttendanceRecords(
    DateTime month,
  ) async {
    final targetMonth = DateTime(month.year, month.month, 1);
    final coll = _attendance;
    if (coll == null) return const [];

    final startOfMonth = targetMonth;
    final startOfNextMonth = DateTime(
      targetMonth.year,
      targetMonth.month + 1,
      1,
    );

    final snapshots = await Future.wait([
      coll
          .where('attendanceDate', isGreaterThanOrEqualTo: startOfMonth)
          .where('attendanceDate', isLessThan: startOfNextMonth)
          .get(),
      coll
          .where('createdAt', isGreaterThanOrEqualTo: startOfMonth)
          .where('createdAt', isLessThan: startOfNextMonth)
          .get(),
    ]);

    final recordsById = <String, Map<String, dynamic>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        recordsById[doc.id] = {
          ...doc.data() as Map<String, dynamic>,
          'id': doc.id,
        };
      }
    }
    return recordsById.values.toList();
  }

  Future<Map<String, int>> getWorkerMonthlyAttendance(
    String email, {
    String? workerId,
    DateTime? month,
    List<Map<String, dynamic>>? preFetchedRecords,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedWorkerId = (workerId ?? '').trim();
    if (normalizedEmail.isEmpty && normalizedWorkerId.isEmpty) {
      return {'absents': 0, 'paidLeaves': 0, 'unpaidLeaves': 0, 'leaves': 0};
    }
    final targetMonth = month ?? DateTime.now();
    List<Map<String, dynamic>> records;
    final isGuest = AuthService.instance.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      records = List<Map<String, dynamic>>.from(DummyData.attendance);
    } else if (preFetchedRecords != null) {
      records = preFetchedRecords;
    } else {
      records = await getMonthlyAttendanceRecords(targetMonth);
    }

    records.sort((a, b) {
      final aDate = AppDateUtils.attendanceRecordDate(a);
      final bDate = AppDateUtils.attendanceRecordDate(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      return (b['id'] ?? '').toString().compareTo((a['id'] ?? '').toString());
    });

    final absentDates = <DateTime>{};
    final legacyLeaveDates = <DateTime>{};
    final seenDays = <String>{};
    for (final att in records) {
      final attendanceWorkerId = (att['workerId'] ?? '').toString().trim();
      final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
      final workerIdMatches =
          normalizedWorkerId.isNotEmpty &&
          attendanceWorkerId.isNotEmpty &&
          normalizedWorkerId == attendanceWorkerId;
      final emailMatches =
          normalizedEmail.isNotEmpty &&
          attEmail.isNotEmpty &&
          normalizedEmail == attEmail;
      // Exact email is a safe fallback for older attendance documents whose
      // worker ID was saved in a different format. Worker emails are unique,
      // and this keeps Add Payroll and Payroll Review on the same identity.
      final identityMatches = workerIdMatches || emailMatches;
      if (!identityMatches) continue;
      final date = AppDateUtils.attendanceRecordDate(att);
      if (date == null) continue;
      if (date.year != targetMonth.year || date.month != targetMonth.month) {
        continue;
      }
      final identityKey = normalizedWorkerId.isNotEmpty
          ? normalizedWorkerId
          : normalizedEmail;
      final dayKey = '$identityKey-${date.year}-${date.month}-${date.day}';
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

    final worker = <String, dynamic>{
      'id': normalizedWorkerId,
      'email': normalizedEmail,
    };
    final planned = TimeOffService.monthlyLeaveCounts(
      worker,
      timeOffRecords,
      month: targetMonth,
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

    final holidayDates = await _getHolidayDatesForMonth(
      targetMonth.year,
      targetMonth.month,
    );
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
    final workingDates = await getWorkingDates(
      from: DateTime(now.year, now.month, 1),
      toExclusive: DateTime(now.year, now.month + 1, 1),
    );
    return workingDates.length;
  }

  Future<Set<DateTime>> getWorkingDates({
    required DateTime from,
    required DateTime toExclusive,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(toExclusive.year, toExclusive.month, toExclusive.day);
    final coll = _holidays;
    var companyWorkingDays = <int>{
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
    };
    if (coll == null) {
      return {
        for (
          var date = start;
          date.isBefore(end);
          date = date.add(const Duration(days: 1))
        )
          if (companyWorkingDays.contains(date.weekday)) date,
      };
    }
    try {
      final snap = await coll.get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['type'] != 'company_work_days') continue;
        final savedDays = (data['workingDays'] as List<dynamic>? ?? [])
            .whereType<num>()
            .map((day) => day.toInt())
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet();
        if (savedDays.isNotEmpty) companyWorkingDays = savedDays;
      }

      final workingDates = <DateTime>{
        for (
          var date = start;
          date.isBefore(end);
          date = date.add(const Duration(days: 1))
        )
          if (companyWorkingDays.contains(date.weekday)) date,
      };
      final holidayDates = <DateTime>{};
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['type'] == 'company_work_days') continue;
        if (data['isEnabled'] == false) continue;
        for (
          var date = start;
          date.isBefore(end);
          date = date.add(const Duration(days: 1))
        ) {
          final holidayDate = AppDateUtils.holidayRecordDate(
            data,
            fallbackYear: date.year,
          );
          if (holidayDate != null &&
              holidayDate.month == date.month &&
              holidayDate.day == date.day &&
              _holidayAppliesToYear(data, date.year)) {
            if (workingDates.contains(date)) holidayDates.add(date);
            break;
          }
        }
      }
      return workingDates.difference(holidayDates);
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'GetWorkingDates');
      rethrow;
    }
  }

  static bool _holidayAppliesToYear(Map<String, dynamic> holiday, int year) {
    if (holiday['isRecurring'] == true) return true;
    final holidayYear = AppDateUtils.holidayRecordDate(
      holiday,
      fallbackYear: year,
    )?.year;

    return holidayYear == null || holidayYear == year;
  }

  Future<Set<DateTime>> _getHolidayDatesForMonth(int year, int month) async {
    final dates = <DateTime>{};
    final coll = _holidays;
    if (coll == null) return dates;
    try {
      final snap = await coll.get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['type'] == 'company_work_days') continue;
        if (data['isEnabled'] == false) continue;
        final holidayDate = AppDateUtils.holidayRecordDate(
          data,
          fallbackYear: year,
        );
        if (_holidayAppliesToYear(data, year) &&
            holidayDate != null &&
            holidayDate.month == month) {
          dates.add(DateTime(year, month, holidayDate.day));
        }
      }
    } catch (_) {}
    return dates;
  }

  Stream<QuerySnapshot> get attendanceStream {
    final coll = _attendance;
    if (coll == null) return const Stream.empty();

    return coll.snapshots();
  }

  Stream<QuerySnapshot> attendanceStreamForPeriod({
    required DateTime start,
    required DateTime end,
  }) {
    final coll = _attendance;
    if (coll == null) return const Stream.empty();
    return coll
        .where(
          'attendanceDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('attendanceDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('attendanceDate', descending: true)
        .snapshots();
  }

  Future<QuerySnapshot> getAttendanceForPeriod(
    DateTime start,
    DateTime end,
  ) async {
    final coll = _attendance;
    if (coll == null) throw StateError('No authenticated user');
    return await coll
        .where(
          'attendanceDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('attendanceDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
  }

  Future<String> addPayrollRecord(Map<String, dynamic> record) async {
    Validators.validatePayroll(record);
    final coll = _payroll;
    if (coll == null) throw StateError('No authenticated user');

    final payrollKey = (record['payrollKey'] ?? '').toString().trim();
    final docRef = payrollKey.isEmpty
        ? coll.doc()
        : coll.doc(_payrollDocumentId(payrollKey));
    final existing = await docRef.get();

    await docRef.set({
      ...record,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final name = (record['name'] ?? record['workerName'] ?? '').toString();
    final amount = (record['netSalary'] ?? record['salary'] ?? '').toString();
    if (name.isNotEmpty) {
      try {
        await addNotification({
          if (payrollKey.isNotEmpty) 'notificationKey': 'payroll_$payrollKey',
          'type': 'payroll_added',
          'title': 'notif_title_payroll'.tr(namedArgs: {'name': name}),
          'message': amount.isNotEmpty
              ? 'notif_msg_payroll_amount'.tr(
                  namedArgs: {'amount': amount, 'name': name},
                )
              : 'notif_msg_payroll'.tr(namedArgs: {'name': name}),
          'data': {'name': name, 'amount': amount},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'PayrollNotification');
      }
    }

    return docRef.id;
  }

  Future<int> addBulkPayrollRecords(List<Map<String, dynamic>> records) async {
    final coll = _payroll;
    if (coll == null) return 0;
    if (records.isEmpty) return 0;

    var saved = 0;
    const chunkSize = 450;
    for (var start = 0; start < records.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, records.length).toInt();
      final chunk = records.sublist(start, end);
      final batch = _db.batch();
      for (final record in chunk) {
        Validators.validatePayroll(record);
        final payrollKey = (record['payrollKey'] ?? '').toString().trim();
        final docRef = payrollKey.isEmpty
            ? coll.doc()
            : coll.doc(_payrollDocumentId(payrollKey));
        batch.set(docRef, {
          ...record,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      saved += chunk.length;
    }

    return saved;
  }

  Future<void> addBulkExpenses(List<Map<String, dynamic>> expenses) async {
    final coll = _expenses;
    if (coll == null) return;

    const chunkSize = 50;
    for (var start = 0; start < expenses.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, expenses.length).toInt();
      final chunk = expenses.sublist(start, end);

      await Future.wait(
        chunk.map((expense) async {
          try {
            Validators.validateExpense(expense);
            final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
            final docRef = payrollKey.isEmpty
                ? coll.doc()
                : coll.doc(_payrollExpenseDocumentId(payrollKey));
            final existing = await docRef.get();

            await docRef.set({
              ...expense,
              if (payrollKey.isNotEmpty) 'payrollKey': payrollKey,
              if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (_) {}
        }),
      );
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
      final notificationKey = (notification['notificationKey'] ?? '')
          .toString()
          .trim();
      final docRef = notificationKey.isEmpty
          ? coll.doc()
          : coll.doc(notificationKey.replaceAll('/', '_'));
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
    if (coll == null || id.trim().isEmpty) return;

    final docRef = coll.doc(id.trim());
    final existingSnapshot = await docRef.get();
    if (!existingSnapshot.exists) {
      throw StateError('Payroll record does not exist');
    }

    final existing =
        existingSnapshot.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final merged = <String, dynamic>{...existing, ...data};
    Validators.validatePayroll(merged);

    await docRef.update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastModified': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePayrollByPayrollKey(
    String payrollKey,
    Map<String, dynamic> data,
  ) async {
    final coll = _payroll;
    if (coll == null || payrollKey.trim().isEmpty) return;

    final snapshot = await coll
        .where('payrollKey', isEqualTo: payrollKey.trim())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return;

    await snapshot.docs.first.reference.update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastModified': FieldValue.serverTimestamp(),
    });
  }

  Future<void> savePayrollAndExpenseBatch({
    required Map<String, dynamic> record,
    required String payrollKey,
    required double netAmount,
    required Map<String, dynamic>? expenseRecord,
    String? existingPayrollId,
  }) async {
    final coll = _payroll;
    if (coll == null) throw StateError('No authenticated user');

    final batch = _db.batch();

    final docRef = existingPayrollId != null && existingPayrollId.isNotEmpty
        ? coll.doc(existingPayrollId.trim())
        : coll.doc(_payrollDocumentId(payrollKey));
    final existingSnapshot = await docRef.get();
    final previousPayrollData = existingSnapshot.data();
    final previousPayrollKey = previousPayrollData is Map<String, dynamic>
        ? (previousPayrollData['payrollKey'] ?? '').toString().trim()
        : '';

    batch.set(docRef, {
      ...record,
      if (!existingSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final normalizedPayrollKey = payrollKey.trim();
    if (_expenses != null && normalizedPayrollKey.isNotEmpty) {
      final expenseRef = _expenses!.doc(
        _payrollExpenseDocumentId(normalizedPayrollKey),
      );
      final linkedPayrollKeys = <String>{
        normalizedPayrollKey,
        if (previousPayrollKey.isNotEmpty) previousPayrollKey,
      };
      final existingExpenseRefs = <String, DocumentReference>{};
      for (final linkedKey in linkedPayrollKeys) {
        final existingExpenses = await _expenses!
            .where('payrollKey', isEqualTo: linkedKey)
            .get();
        for (final expense in existingExpenses.docs) {
          existingExpenseRefs[expense.reference.path] = expense.reference;
        }
        final deterministicRef = _expenses!.doc(
          _payrollExpenseDocumentId(linkedKey),
        );
        existingExpenseRefs[deterministicRef.path] = deterministicRef;
      }

      if (netAmount > 0 && expenseRecord != null) {
        final expenseSnapshot = await expenseRef.get();
        batch.set(expenseRef, {
          ...expenseRecord,
          'payrollKey': normalizedPayrollKey,
          if (!expenseSnapshot.exists)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        batch.delete(expenseRef);
      }

      for (final reference in existingExpenseRefs.values) {
        if (reference.path != expenseRef.path) {
          batch.delete(reference);
        }
      }

      if (_notifications != null &&
          previousPayrollKey.isNotEmpty &&
          previousPayrollKey != normalizedPayrollKey) {
        batch.delete(
          _notifications!.doc(
            _payrollNotificationDocumentId(previousPayrollKey),
          ),
        );
      }
    }

    await batch.commit();
  }

  Future<void> deletePayrollRecord(String id) async {
    final coll = _payroll;
    if (coll == null || id.trim().isEmpty) return;

    final payrollRef = coll.doc(id.trim());
    final payrollSnapshot = await payrollRef.get();
    if (!payrollSnapshot.exists) return;

    final payrollData =
        payrollSnapshot.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final payrollKey = (payrollData['payrollKey'] ?? '').toString().trim();

    final expenseDocs = payrollKey.isEmpty || _expenses == null
        ? <QueryDocumentSnapshot>[]
        : (await _expenses!.where('payrollKey', isEqualTo: payrollKey).get())
              .docs;

    final batch = _db.batch();
    batch.delete(payrollRef);

    for (final expense in expenseDocs) {
      batch.delete(expense.reference);
    }

    if (_notifications != null && payrollKey.isNotEmpty) {
      batch.delete(
        _notifications!.doc(_payrollNotificationDocumentId(payrollKey)),
      );
    }

    await batch.commit();
  }

  Future<void> cancelPayrollRecord({
    required String payrollId,
    required String payrollKey,
  }) async {
    final payrollColl = _payroll;
    if (payrollColl == null || payrollId.trim().isEmpty) {
      throw StateError('Payroll record is unavailable');
    }

    final expenseDocs = payrollKey.trim().isEmpty || _expenses == null
        ? <QueryDocumentSnapshot>[]
        : (await _expenses!
                  .where('payrollKey', isEqualTo: payrollKey.trim())
                  .get())
              .docs;
    final batch = _db.batch();
    batch.update(payrollColl.doc(payrollId), {
      'status': 'Unpaid',
      'isPaid': false,
      'paid': false,
      'paymentStatus': 'unpaid',
      'paidAt': FieldValue.delete(),
      'paidOn': FieldValue.delete(),
      'paymentDate': FieldValue.delete(),
      'cancelledAt': FieldValue.serverTimestamp(),
      'lastModified': FieldValue.serverTimestamp(),
    });
    final expenseRefs = <String, DocumentReference>{
      for (final expense in expenseDocs)
        expense.reference.path: expense.reference,
    };
    if (_expenses != null && payrollKey.trim().isNotEmpty) {
      final deterministicRef = _expenses!.doc(
        _payrollExpenseDocumentId(payrollKey.trim()),
      );
      expenseRefs[deterministicRef.path] = deterministicRef;
    }
    for (final reference in expenseRefs.values) {
      batch.delete(reference);
    }
    if (_notifications != null && payrollKey.trim().isNotEmpty) {
      batch.delete(
        _notifications!.doc(
          'payroll_${payrollKey.trim()}'.replaceAll('/', '_'),
        ),
      );
    }
    await batch.commit();
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
      try {
        await addNotification({
          'type': 'time_off_added',
          'title': 'notif_title_time_off'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_time_off'.tr(
            namedArgs: {'type': type, 'name': name},
          ),
          'data': {'name': name, 'type': type},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'TimeOffNotification');
      }
    }
    return docRef.id;
  }

  Future<void> updateTimeOffRecord(String id, Map<String, dynamic> data) async {
    final coll = _timeoff;
    if (coll == null) return;
    await coll.doc(id).update(data);
  }

  Future<void> cancelTimeOffRecord(String id) async {
    final coll = _timeoff;
    if (coll == null) return;
    await coll.doc(id).update({
      'status': 'Cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelTimeOffWithWorkerBalance({
    required String timeOffId,
    required String workerId,
  }) async {
    final timeOffColl = _timeoff;
    final workersColl = _workers;
    if (timeOffColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }

    final timeOffRef = timeOffColl.doc(timeOffId);
    final workerRef = workersColl.doc(workerId);
    final currentTimeOffSnapshot = await timeOffColl.get();
    final currentTimeOffRecords = currentTimeOffSnapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();

    await _db.runTransaction((transaction) async {
      final timeOffSnapshot = await transaction.get(timeOffRef);
      if (!timeOffSnapshot.exists) {
        throw StateError('Time off record does not exist');
      }
      final timeOffData =
          (timeOffSnapshot.data() as Map<String, dynamic>?) ?? {};
      if (!TimeOffService.isActiveRecord(timeOffData)) return;
      final oldDates = TimeOffService.selectedDatesForRecord(timeOffData);

      final workerSnapshot = await transaction.get(workerRef);
      final workerData = workerSnapshot.exists
          ? (workerSnapshot.data() as Map<String, dynamic>?) ?? {}
          : <String, dynamic>{};

      final attendanceSnapshots = <String, DocumentSnapshot>{};
      final attendanceColl = _attendance;
      if (attendanceColl != null && oldDates.isNotEmpty) {
        final datesList = oldDates.toList();
        final snapshots = await Future.wait(
          datesList.map(
            (d) => transaction.get(
              attendanceColl.doc(_attendanceDocumentId(workerId, d)),
            ),
          ),
        );
        for (int i = 0; i < datesList.length; i++) {
          attendanceSnapshots[_timeOffDateKey(datesList[i])] = snapshots[i];
        }
      }

      Map<String, dynamic>? workerBalanceUpdate;
      if (workerSnapshot.exists) {
        final dateLocks = workerData['timeOffDateLocks'] is Map
            ? Map<String, dynamic>.from(workerData['timeOffDateLocks'] as Map)
            : <String, dynamic>{};
        for (final date in oldDates) {
          final key = _timeOffDateKey(date);
          if (dateLocks[key]?.toString() == timeOffId) dateLocks.remove(key);
        }

        final recordsAfterCancellation =
            currentTimeOffRecords
                .where((record) => record['id']?.toString() != timeOffId)
                .map(Map<String, dynamic>.from)
                .toList()
              ..add({...timeOffData, 'id': timeOffId, 'status': 'Cancelled'});
        final workerWithId = {
          ...workerData,
          'id': workerId,
          'workerId': workerId,
        };
        workerBalanceUpdate = TimeOffService.canonicalWorkerLeaveFields(
          workerWithId,
          remainingBalances:
              TimeOffService.remainingBalancesFromAssignedRecords(
                workerWithId,
                recordsAfterCancellation,
              ),
        );
        workerBalanceUpdate = {
          ...workerBalanceUpdate,
          'timeOffDateLocks': dateLocks,
        };
      }

      transaction.update(timeOffRef, {
        'status': 'Cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (workerBalanceUpdate != null) {
        transaction.update(workerRef, workerBalanceUpdate);
      }
      for (final snapshot in attendanceSnapshots.values) {
        if (!snapshot.exists) continue;
        final attendance =
            (snapshot.data() as Map<String, dynamic>?) ?? const {};
        final source = (attendance['source'] ?? '').toString();
        final linkedId = (attendance['timeOffId'] ?? '').toString().trim();
        if (source == 'auto_leave' &&
            (linkedId.isEmpty || linkedId == timeOffId)) {
          transaction.delete(snapshot.reference);
        }
      }
    });
  }

  Future<String> saveTimeOffWithWorkerBalance({
    String? timeOffId,
    required Map<String, dynamic> record,
    required String workerId,
    required String leaveType,
    required int requestedDays,
  }) async {
    Validators.validateTimeOff(record);
    final timeOffColl = _timeoff;
    final workersColl = _workers;
    if (timeOffColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }
    final isNew = timeOffId == null || timeOffId.isEmpty;

    final leaveField = switch (TimeOffService.normalizeLeaveType(leaveType)) {
      'Annual Leave' => 'annualLeave',
      'Sick Leave' => 'sickLeave',
      'Casual Leave' => 'casualLeave',
      'Medical Leave' => 'medicalLeave',
      _ => '',
    };

    if (leaveField.isEmpty) {
      throw StateError('Invalid leave type: $leaveType');
    }

    final docId = isNew
        ? '${workerId.replaceAll(RegExp(r'\s+'), '')}_${DateTime.now().millisecondsSinceEpoch}'
        : timeOffId;
    final timeOffRef = timeOffColl.doc(docId);
    final workerRef = workersColl.doc(workerId);
    final newDates = TimeOffService.selectedDatesForRecord(record);
    if (newDates.isEmpty || requestedDays != newDates.length) {
      throw ArgumentError('requestedDays must match the selected leave dates');
    }
    final currentTimeOffSnapshot = await timeOffColl.get();
    final currentTimeOffRecords = currentTimeOffSnapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();

    await _db.runTransaction((transaction) async {
      final workerSnapshot = await transaction.get(workerRef);
      if (!workerSnapshot.exists) {
        throw StateError('Worker does not exist');
      }

      final workerData = (workerSnapshot.data() as Map<String, dynamic>?) ?? {};

      var oldDates = const <DateTime>[];
      if (!isNew) {
        final existingRecordSnapshot = await transaction.get(timeOffRef);
        if (!existingRecordSnapshot.exists) {
          throw StateError('Time off record does not exist');
        }
        final oldRecordData =
            (existingRecordSnapshot.data() as Map<String, dynamic>?) ?? {};
        oldDates = TimeOffService.selectedDatesForRecord(oldRecordData);
        if (TimeOffService.hasPastDateModification(
          oldDates: oldDates,
          newDates: newDates,
        )) {
          throw const PastTimeOffEditException();
        }

        final oldWorkerId = (oldRecordData['workerId'] ?? '').toString().trim();
        if (oldWorkerId.isNotEmpty && oldWorkerId != workerId) {
          throw StateError('The worker on an existing time off cannot change');
        }
        if (!TimeOffService.recordHasLeaveType(oldRecordData, leaveType)) {
          throw StateError(
            'An existing time off record cannot be changed to another leave type',
          );
        }
      }

      final attendanceSnapshots = <String, DocumentSnapshot>{};
      final attendanceColl = _attendance;
      if (attendanceColl != null) {
        final datesList = {...oldDates, ...newDates}.toList();
        if (datesList.isNotEmpty) {
          final snapshots = await Future.wait(
            datesList.map(
              (d) => transaction.get(
                attendanceColl.doc(_attendanceDocumentId(workerId, d)),
              ),
            ),
          );
          for (int i = 0; i < datesList.length; i++) {
            attendanceSnapshots[_timeOffDateKey(datesList[i])] = snapshots[i];
          }
        }
      }

      final dateLocks = workerData['timeOffDateLocks'] is Map
          ? Map<String, dynamic>.from(workerData['timeOffDateLocks'] as Map)
          : <String, dynamic>{};
      for (final date in oldDates) {
        final key = _timeOffDateKey(date);
        if (dateLocks[key]?.toString() == docId) dateLocks.remove(key);
      }
      for (final date in newDates) {
        final key = _timeOffDateKey(date);
        final owner = (dateLocks[key] ?? '').toString().trim();
        if (owner.isNotEmpty && owner != docId) {
          throw const DuplicateTimeOffDateException();
        }
        dateLocks[key] = docId;
      }

      final workerWithId = {
        ...workerData,
        'id': workerId,
        'workerId': workerId,
      };
      // The screen also checks overlaps, but its worker-specific stream can
      // still be loading when Save is clicked. Always repeat the check here
      // against the complete Time Off collection so an Attendance-created
      // leave and a manually assigned Time Off cannot consume the same date.
      if (TimeOffService.hasOverlappingApprovedLeave(
        workerWithId,
        currentTimeOffRecords,
        newDates,
        excludingRecordId: isNew ? null : docId,
      )) {
        throw const DuplicateTimeOffDateException();
      }
      final actualAvailable = TimeOffService.remainingForType(
        workerWithId,
        currentTimeOffRecords,
        leaveType,
        excludingRecordId: isNew ? null : docId,
      );
      if (requestedDays > actualAvailable) {
        throw StateError('Insufficient $leaveType balance');
      }

      final recordsAfterSave =
          currentTimeOffRecords
              .where((existing) => existing['id']?.toString() != docId)
              .map(Map<String, dynamic>.from)
              .toList()
            ..add({...record, 'id': docId});
      final leaveBalances = TimeOffService.remainingBalancesFromAssignedRecords(
        workerWithId,
        recordsAfterSave,
      );

      final workerUpdates = TimeOffService.canonicalWorkerLeaveFields(
        workerWithId,
        remainingBalances: leaveBalances,
      )..['timeOffDateLocks'] = dateLocks;

      transaction.update(workerRef, workerUpdates);

      transaction.set(timeOffRef, {
        ...record,
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final newDateKeys = newDates.map(_timeOffDateKey).toSet();
      final normalizedType = TimeOffService.normalizeLeaveType(leaveType);
      for (final entry in attendanceSnapshots.entries) {
        final snapshot = entry.value;
        if (!snapshot.exists) continue;
        final attendance =
            (snapshot.data() as Map<String, dynamic>?) ?? const {};
        final source = (attendance['source'] ?? '').toString();
        final linkedId = (attendance['timeOffId'] ?? '').toString().trim();
        if (source != 'auto_leave' ||
            (linkedId.isNotEmpty && linkedId != docId)) {
          continue;
        }
        if (newDateKeys.contains(entry.key)) {
          transaction.set(snapshot.reference, {
            'status': 'Leave',
            'type': normalizedType,
            'source': 'auto_leave',
            'timeOffId': docId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          transaction.delete(snapshot.reference);
        }
      }
    });

    if (isNew) {
      final name = (record['workerName'] ?? record['name'] ?? '').toString();
      final type = (record['type'] ?? record['leaveType'] ?? 'Leave')
          .toString();
      if (name.isNotEmpty) {
        unawaited(
          addNotification({
            'type': 'time_off_added',
            'title': 'notif_title_time_off'.tr(namedArgs: {'name': name}),
            'message': 'notif_msg_time_off'.tr(
              namedArgs: {'type': type, 'name': name},
            ),
            'data': {'name': name, 'type': type},
          }).then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              ErrorReporter.report(
                error,
                stackTrace,
                context: 'TimeOffBalanceNotification',
              );
            },
          ),
        );
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

  Stream<QuerySnapshot> timeoffForWorkerStream(String workerId) {
    final coll = _timeoff;
    if (coll == null || workerId.trim().isEmpty) {
      return const Stream.empty();
    }
    return coll.where('workerId', isEqualTo: workerId.trim()).snapshots();
  }

  Future<QuerySnapshot> getTimeoffForWorker(String workerId) async {
    final coll = _timeoff;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.where('workerId', isEqualTo: workerId).get();
  }

  Future<String> addAsset(Map<String, dynamic> asset) async {
    final canonicalAsset = _canonicalAssetReturnFields(asset);
    Validators.validateAsset(canonicalAsset);
    final coll = _assets;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...canonicalAsset,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final workerName =
        (canonicalAsset['name'] ?? canonicalAsset['assetName'] ?? '')
            .toString();
    final assetType =
        (canonicalAsset['type'] ?? canonicalAsset['assetType'] ?? '')
            .toString();
    if (workerName.isNotEmpty) {
      try {
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
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'AssetNotification');
      }
    }
    return docRef.id;
  }

  Future<void> updateAsset(String id, Map<String, dynamic> data) async {
    final canonicalData = _canonicalAssetReturnFields(data);
    Validators.validateAsset(canonicalData);
    final coll = _assets;
    if (coll == null) return;
    await coll.doc(id).update(canonicalData);
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

  Future<QuerySnapshot> getAssetsOnce({int limit = 50}) async {
    final coll = _assets;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.orderBy('createdAt', descending: true).limit(limit).get();
  }

  Future<String> addHoliday(Map<String, dynamic> holiday) async {
    final canonicalHoliday = _canonicalHolidayFields(holiday, forUpdate: false);
    Validators.validateHoliday(canonicalHoliday);
    final coll = _holidays;
    if (coll == null) throw StateError('No authenticated user');
    final docRef = await coll.add({
      ...canonicalHoliday,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final name = (canonicalHoliday['name'] ?? '').toString();
    if (name.isNotEmpty) {
      try {
        addNotification({
          'type': 'holiday_added',
          'title': 'notif_title_holiday'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_holiday'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        });
      } catch (error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'HolidayNotification');
      }
    }
    return docRef.id;
  }

  Future<void> updateHoliday(String id, Map<String, dynamic> data) async {
    final canonicalData = _canonicalHolidayFields(data, forUpdate: true);
    if (canonicalData.containsKey('name')) {
      Validators.validateHoliday(canonicalData);
    }
    final coll = _holidays;
    if (coll == null) return;
    await coll.doc(id).update(canonicalData);
  }

  Future<void> deleteHoliday(String id) async {
    final coll = _holidays;
    if (coll == null) return;
    await coll.doc(id).delete();
  }

  Stream<QuerySnapshot> get holidaysStream {
    final coll = _holidays;
    if (coll == null) return const Stream.empty();
    return coll.orderBy('createdAt', descending: true).snapshots().asyncMap((
      snapshot,
    ) async {
      await _migrateHolidaySchema(snapshot);
      return snapshot;
    });
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
        'isDummyData': true,
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
        'isDummyData': true,
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
        'isDummyData': true,
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
        'isDummyData': true,
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
        'isDummyData': true,
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
          'isDummyData': true,
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
        'isDummyData': true,
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
    final notificationKey = (notification['notificationKey'] ?? '')
        .toString()
        .trim();
    final data = {
      ...notification,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (notificationKey.isEmpty) {
      await coll.add(data);
    } else {
      await coll
          .doc(notificationKey.replaceAll('/', '_'))
          .set(data, SetOptions(merge: true));
    }
  }

  Future<bool> addNotificationIfAbsent(
    String notificationKey,
    Map<String, dynamic> notification,
  ) async {
    final coll = _notifications;
    final normalizedKey = notificationKey.trim().replaceAll('/', '_');
    if (coll == null || normalizedKey.isEmpty) return false;
    final docRef = coll.doc(normalizedKey);
    return _db.runTransaction<bool>((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) return false;
      transaction.set(docRef, {
        ...notification,
        'notificationKey': notificationKey.trim(),
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<bool> upsertNotificationByKey(
    String notificationKey,
    Map<String, dynamic> notification,
  ) async {
    final coll = _notifications;
    final normalizedKey = notificationKey.trim().replaceAll('/', '_');
    if (coll == null || normalizedKey.isEmpty) return false;
    final docRef = coll.doc(normalizedKey);
    return _db.runTransaction<bool>((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) {
        transaction.set(docRef, {
          ...notification,
          'notificationKey': notificationKey.trim(),
        }, SetOptions(merge: true));
        return false;
      }
      transaction.set(docRef, {
        ...notification,
        'notificationKey': notificationKey.trim(),
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
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
    if (unread.docs.isEmpty) return;

    var batch = _db.batch();
    var pending = 0;
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
      pending++;
      if (pending == 450) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }
    if (pending > 0) {
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
    if (snap.docs.isEmpty) return;
    await _deleteDocumentsInChunks(snap.docs.map((doc) => doc.reference));
  }

  Future<List<Map<String, dynamic>>> getPolicies() async {
    return [];
  }

  Future<List<Map<String, dynamic>>> getLeavePolicies() async {
    return [];
  }
}
