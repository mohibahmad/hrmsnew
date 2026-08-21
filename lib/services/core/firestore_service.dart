import 'package:hrms/models/worker.dart';
import 'package:hrms/core/utils/utils.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/attendance/attendance_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/time_off/time_off_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/services/payroll/payroll_service.dart';

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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService Function()? _authService;
  final Set<String> _leaveNormalizationInFlight = <String>{};
  bool _holidaySchemaMigrationInFlight = false;

  FirestoreService({AuthService Function()? authService})
    : _authService = authService {
    _instance = this;
  }

  AuthService get _auth => _authService?.call() ?? AuthService.instance;

  dynamic _sanitizeFirestoreValue(dynamic value, {required bool isNewDoc}) {
    if (value == null) return null;
    if (isNewDoc && value is FieldValue && value == FieldValue.delete()) {
      return null;
    }
    if (value is FieldValue || value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    if (value is num) return value.isFinite ? value : null;
    if (value is bool) return value;
    if (value is String) {
      if (value.startsWith('data:') && value.contains(';base64,')) return null;
      return value;
    }
    if (value is Set) {
      return value
          .map((e) => _sanitizeFirestoreValue(e, isNewDoc: isNewDoc))
          .where((e) => e != null)
          .toList();
    }
    if (value is List) {
      return value
          .map((e) => _sanitizeFirestoreValue(e, isNewDoc: isNewDoc))
          .where((e) => e != null)
          .toList();
    }
    if (value is Map) {
      final cleanMap = <String, dynamic>{};
      value.forEach((k, v) {
        final cleanKey = k.toString();
        final cleanVal = _sanitizeFirestoreValue(v, isNewDoc: isNewDoc);
        if (cleanVal != null || !isNewDoc) cleanMap[cleanKey] = cleanVal;
      });
      return cleanMap;
    }
    return value.toString();
  }

  Map<String, dynamic> _withNormalizedCurrency(
    Map<String, dynamic> data, {
    bool isNewDoc = true,
  }) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized.containsKey('currency')) {
      normalized['currency'] = CurrencyUtils.normalize(normalized['currency']);
    }
    if (normalized.containsKey('type1') || normalized.containsKey('workType')) {
      final val = normalized['workType'] ?? normalized['type1'];
      if (val != null) {
        normalized['workType'] = val;
      }
      normalized.remove('type1');
    }
    if (normalized.containsKey('type2') ||
        normalized.containsKey('attendanceType')) {
      final val = normalized['attendanceType'] ?? normalized['type2'];
      if (val != null) {
        normalized['attendanceType'] = val;
      }
      normalized.remove('type2');
    }
    final sanitized = _sanitizeFirestoreValue(normalized, isNewDoc: isNewDoc);
    return sanitized is Map<String, dynamic>
        ? sanitized
        : Map<String, dynamic>.from(sanitized as Map);
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
      var batch = _firestore.batch();
      var writes = 0;
      for (final entry in migrations.entries) {
        batch.update(entry.key, entry.value);
        writes++;
        if (writes == 450) {
          await batch.commit();
          batch = _firestore.batch();
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
    return '${workerId}_${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
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
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteDocumentsInChunks(
    Iterable<DocumentReference> references,
  ) async {
    var batch = _firestore.batch();
    var pending = 0;
    for (final reference in references) {
      batch.delete(reference);
      pending++;
      if (pending == 450) {
        await batch.commit();
        batch = _firestore.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
  }

  String get _userKey {
    final user = _auth.currentUser;
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
    return _firestore.collection('hrms_user').doc(key);
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
    final user = _auth.currentUser;
    if (user == null ||
        user.isAnonymous ||
        user.uid == 'guest_uid' ||
        user.uid.startsWith('guest_')) {
      return;
    }
    final doc = _firestore.collection('hrms_user').doc(user.uid);
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
      var batch = _firestore.batch();
      int count = 0;
      for (final d in snapshot.docs) {
        batch.delete(d.reference);
        count++;
        if (count % 500 == 0) {
          await batch.commit();
          batch = _firestore.batch();
        }
      }
      if (count % 500 != 0 && count > 0) await batch.commit();
    }
    await doc.update({'hasDummyData': false});
  }

  Future<bool> isCurrentUserDeleted() async {
    final profile = await getUserProfile();
    return profile?['isDeleted'] == true;
  }

  Future<bool> isEmailDeleted(String email) async {
    if (email.trim().isEmpty) return false;
    final snapshot = await _firestore
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
    } catch (_) {
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

    final duplicateField = await findDuplicateWorkerField(
      email: (worker['email'] ?? '').toString(),
      nationalId: (worker['nationalId'] ?? '').toString(),
    );
    if (duplicateField != null) throw DuplicateWorkerException(duplicateField);

    final canonicalWorker = WorkerModel.fromMap(worker).toFirestore();

    final docRef = await coll.add({
      ..._withNormalizedCurrency(canonicalWorker, isNewDoc: true),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final name = (worker['name'] ?? '').toString();
    if (name.isNotEmpty) {
      unawaited(
        addNotification({
          'type': 'worker_added',
          'title': 'notif_title_new_member'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_new_member'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        }).catchError((error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'WorkerNotification',
          );
        }),
      );
    }
    return docRef.id;
  }

  Future<BulkWorkerResult> addBulkWorkers(
    List<Map<String, dynamic>> workersList, {
    Set<String>? existingEmails,
    Set<String>? existingNationalIds,
  }) async {
    final coll = _workers;
    if (coll == null) {
      return BulkWorkerResult(imported: 0, skipped: workersList.length);
    }

    final emails = <String>{...?existingEmails};
    final nationalIds = <String>{...?existingNationalIds};

    if (existingEmails == null || existingNationalIds == null) {
      final existingSnapshot = await coll.get();
      for (final doc in existingSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final e = WorkerIdentity.normalizeEmail(data['email']);
        if (e.isNotEmpty) emails.add(e);
        final n = WorkerIdentity.normalizeNationalId(data['nationalId']);
        if (n.isNotEmpty) nationalIds.add(n);
      }
    }

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
        if (email.isNotEmpty && emails.contains(email)) {
          dupField = 'Email';
        } else if (nationalId.isNotEmpty && nationalIds.contains(nationalId)) {
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

        if (email.isNotEmpty) emails.add(email);
        if (nationalId.isNotEmpty) nationalIds.add(nationalId);
        validWorkers.add(worker);
      } catch (e) {
        skipped++;
        if (clientRowId.isNotEmpty) skippedClientRowIds.add(clientRowId);
        skipReasons.add('Validation error: ${e.toString()}');
      }
    }

    int count = 0;
    if (validWorkers.isNotEmpty) {
      count = validWorkers.length;
      const batchSize = 100;
      final pending = <Future<void>>[];
      for (var i = 0; i < validWorkers.length; i += batchSize) {
        final chunk = validWorkers.sublist(
          i,
          (i + batchSize).clamp(0, validWorkers.length),
        );
        pending.add(_commitBatch(coll, chunk));
      }
      await Future.wait(pending);
      unawaited(_notifyBulkWorkersAdded(count));
    }

    return BulkWorkerResult(
      imported: count,
      skipped: skipped,
      skipReasons: skipReasons,
      skippedClientRowIds: skippedClientRowIds,
    );
  }

  Future<void> _notifyBulkWorkersAdded(int count) async {
    try {
      await addNotification({
        'type': 'worker_added',
        'title': 'notif_title_bulk_workers'.tr(),
        'message': 'notif_msg_bulk_workers'.tr(namedArgs: {'count': '$count'}),
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

  Future<void> _commitBatch(
    CollectionReference coll,
    List<Map<String, dynamic>> workers,
  ) async {
    final batch = _firestore.batch();
    for (final worker in workers) {
      final docRef = coll.doc();
      final canonicalWorker = WorkerModel.fromMap(worker).toFirestore();

      final dataToSet = _withNormalizedCurrency(
        canonicalWorker,
        isNewDoc: true,
      );
      dataToSet['createdAt'] = FieldValue.serverTimestamp();
      batch.set(docRef, dataToSet);
    }
    await batch.commit();
  }

  Future<void> updateWorker(String id, Map<String, dynamic> data) async {
    Validators.validateWorker(data);
    final coll = _workers;
    if (coll == null) return;

    final duplicateField = await findDuplicateWorkerField(
      email: (data['email'] ?? '').toString(),
      nationalId: (data['nationalId'] ?? '').toString(),
      excludeId: id,
    );
    if (duplicateField != null) throw DuplicateWorkerException(duplicateField);

    final currentDoc = await coll.doc(id).get();
    final currentWorker = currentDoc.exists
        ? {...currentDoc.data() as Map<String, dynamic>, 'id': id}
        : <String, dynamic>{};

    if (currentWorker.isNotEmpty) {
      final normalizedName = WorkerIdentity.normalizeName(
        currentWorker['name'],
      );
      await _backfillLegacyWorkerReferences(
        workerId: id,
        previousWorker: currentWorker,
        allowNameFallback: normalizedName.isNotEmpty,
      );
    }

    final workerUpdate = <String, dynamic>{...currentWorker, ...data};
    final timeOffRecords = await getTimeoffOnce(workerId: id);
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
          '$assigned $type days are already assigned. The allowance cannot be set below $assigned.',
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
    var batch = _firestore.batch();
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
          batch = _firestore.batch();
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
    await _firestore.runTransaction((transaction) async {
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
    final timeOffRecords = timeOffSnapshot == null
        ? const <Map<String, dynamic>>[]
        : firestoreRecords(timeOffSnapshot);
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
    final docRef = coll.doc(id);
    final snap = await docRef.get();
    if (!snap.exists) throw StateError('Worker no longer exists');
    final data = snap.data() as Map<String, dynamic>? ?? {};
    if (data['isDeleted'] == true || data['status'] == 'Terminated') {
      throw StateError('Worker no longer exists');
    }
    await docRef.update({
      ..._withNormalizedCurrency(fields),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    var batch = _firestore.batch();
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
        batch = _firestore.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
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
    final policyTimeOffRecords = policyTimeOffSnapshot == null
        ? const <Map<String, dynamic>>[]
        : firestoreRecords(policyTimeOffSnapshot);

    var updated = 0;
    var batch = _firestore.batch();
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
        batch = _firestore.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
    return updated;
  }

  Future<List<Map<String, dynamic>>> getTimeoffOnce({String? workerId}) async {
    final coll = _timeoff;
    if (coll == null) return const [];
    Query query = coll;
    if (workerId != null && workerId.trim().isNotEmpty) {
      query = query.where('workerId', isEqualTo: workerId.trim());
    }
    final snapshot = await query.get();
    return firestoreRecords(snapshot);
  }

  Future<void> deleteWorker(String id) async {
    final workersColl = _workers;
    if (workersColl == null || id.trim().isEmpty) return;
    await workersColl.doc(id.trim()).delete();
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
              .catchError(
                (Object error, StackTrace stackTrace) => ErrorReporter.report(
                  error,
                  stackTrace,
                  context: 'NormalizeWorkerLeaveSchema',
                ),
              )
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

    final normEmail = WorkerIdentity.normalizeEmail(email);
    final rawNationalId = (nationalId ?? '').trim();
    final normNationalId = WorkerIdentity.normalizeNationalId(nationalId);

    if (normEmail.isEmpty && rawNationalId.isEmpty && normNationalId.isEmpty) {
      return null;
    }

    final futures = <Future<QuerySnapshot?>>[];

    if (normEmail.isNotEmpty) {
      futures.add(coll.where('email', isEqualTo: normEmail).limit(2).get());
    } else {
      futures.add(Future.value(null));
    }

    if (rawNationalId.isNotEmpty) {
      futures.add(
        coll.where('nationalId', isEqualTo: rawNationalId).limit(2).get(),
      );
    } else {
      futures.add(Future.value(null));
    }

    final results = await Future.wait(futures);

    final emailSnap = results[0];
    if (emailSnap != null) {
      for (final doc in emailSnap.docs) {
        if (excludeId != null && doc.id == excludeId) continue;
        return DuplicateWorkerField.email;
      }
    }

    final nationalIdSnap = results[1];
    if (nationalIdSnap != null && nationalIdSnap.docs.isNotEmpty) {
      for (final doc in nationalIdSnap.docs) {
        if (excludeId != null && doc.id == excludeId) continue;
        return DuplicateWorkerField.nationalId;
      }
    } else if (normNationalId.isNotEmpty && normNationalId != rawNationalId) {
      final normNatSnap = await coll
          .where('nationalId', isEqualTo: normNationalId)
          .limit(2)
          .get();
      for (final doc in normNatSnap.docs) {
        if (excludeId != null && doc.id == excludeId) continue;
        return DuplicateWorkerField.nationalId;
      }
    }

    return null;
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
    unawaited(
      addNotification({
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
      }).catchError((error, stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'ExpenseNotification');
      }),
    );
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
    final batch = _firestore.batch();
    batch.update(expensesColl.doc(expenseId.trim()), {
      ...expenseData,
      'amount': netAmount,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final payroll in payrollDocs.docs) {
      final pData = payroll.data() as Map<String, dynamic>;
      final baseSalary = PayrollService.extractSalary(
        pData['salary'] ?? pData['salaryAmount'],
      );
      final double overtime, absenceDeduction;
      if (netAmount >= baseSalary) {
        overtime = netAmount - baseSalary;
        absenceDeduction = 0.0;
      } else {
        overtime = 0.0;
        absenceDeduction = baseSalary - netAmount;
      }
      final formatted = PayrollService.formatAmountInCurrency(
        netAmount,
        currency,
      );
      final now = FieldValue.serverTimestamp();
      batch.update(payroll.reference, {
        'netSalaryAmount': netAmount,
        'netSalary': formatted,
        'netSalaryFormatted': formatted,
        'salaryAfterDeduction': formatted,
        'amount': netAmount,
        'overtimeAmount': overtime,
        'absentDeduction': absenceDeduction,
        'leaveDeduction': 0.0,
        'updatedAt': now,
        'lastModified': now,
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

    final batch = _firestore.batch();
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
      final batch = _firestore.batch();
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
    final batch = _firestore.batch();
    batch.delete(expensesColl.doc(expenseId.trim()));
    if (normalizedKey.isNotEmpty) {
      batch.delete(expensesColl.doc(_payrollExpenseDocumentId(normalizedKey)));
    }
    for (final payroll in payrollDocs.docs) {
      batch.delete(payroll.reference);
    }
    if (_notifications != null && normalizedKey.isNotEmpty) {
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
    if (attendanceDate == null) {
      throw ArgumentError(
        'Valid attendanceDate is required for attendance record',
      );
    }
    final now = attendanceDate;
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
      unawaited(
        addNotification({
          'type': 'attendance_marked',
          'title': 'notif_title_attendance'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_attendance'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        }).catchError((error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'AttendanceNotification',
          );
        }),
      );
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
    if (attendanceDate == null) {
      throw ArgumentError(
        'Valid attendanceDate is required for attendance update',
      );
    }
    final targetDate = DateTime(
      attendanceDate.year,
      attendanceDate.month,
      attendanceDate.day,
    );
    final workerId = (data['workerId'] ?? '').toString().trim();

    if (workerId.isNotEmpty) {
      final existingForTarget = await _attendanceCreateTarget(
        coll,
        workerId,
        targetDate,
      );
      if (existingForTarget.alreadyExistsForDate &&
          existingForTarget.reference.id != id) {
        await existingForTarget.reference.set({
          ...data,
          'attendanceDate': Timestamp.fromDate(targetDate),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await coll.doc(id).delete();
        return;
      }
    }
    await coll.doc(id).update({
      ...data,
      'attendanceDate': Timestamp.fromDate(targetDate),
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

    final batch = _firestore.batch();
    final attendanceDate = AppDateUtils.dateFromValue(
      attendanceRecord['attendanceDate'] ?? attendanceRecord['date'],
    );
    final now = attendanceDate ?? DateTime.now();
    final normalizedWorkerId = (workerId ?? '').trim();

    final callerHasNoAttendanceId =
        attendanceId == null || attendanceId.trim().isEmpty;
    if (callerHasNoAttendanceId && normalizedWorkerId.isEmpty) {
      throw ArgumentError(
        'workerId is required when creating a new attendance record to ensure a deterministic document ID.',
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
      unawaited(
        addNotification({
          'type': 'attendance_marked',
          'title': 'notif_title_attendance'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_attendance'.tr(namedArgs: {'name': name}),
          'data': {'name': name},
        }).catchError((error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'attendanceLeaveNotification',
          );
        }),
      );
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
    DateTime? startDate,
    DateTime? endDate,
    List<Map<String, dynamic>>? preFetchedRecords,
    List<Map<String, dynamic>>? preFetchedTimeOffRecords,
    Set<DateTime>? preFetchedHolidayDates,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedWorkerId = (workerId ?? '').trim();
    if (normalizedEmail.isEmpty && normalizedWorkerId.isEmpty) {
      return {'absents': 0, 'paidLeaves': 0, 'unpaidLeaves': 0, 'leaves': 0};
    }
    final targetMonth = month ?? DateTime.now();
    List<Map<String, dynamic>> records;
    final isGuest = _auth.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      records = List<Map<String, dynamic>>.from(DummyData.attendance);
    } else if (preFetchedRecords != null) {
      records = preFetchedRecords;
    } else {
      records = await getMonthlyAttendanceRecords(targetMonth);
    }

    if (preFetchedRecords == null) {
      records.sort((a, b) {
        final aDate = AppDateUtils.attendanceRecordDate(a);
        final bDate = AppDateUtils.attendanceRecordDate(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = bDate.compareTo(aDate);
        if (byDate != 0) return byDate;
        final aUpdated =
            AppDateUtils.dateFromValue(a['updatedAt'] ?? a['createdAt']) ??
            DateTime(1970);
        final bUpdated =
            AppDateUtils.dateFromValue(b['updatedAt'] ?? b['createdAt']) ??
            DateTime(1970);
        return bUpdated.compareTo(aUpdated);
      });
    }

    final workerIdentity = <String, dynamic>{
      'id': normalizedWorkerId,
      'email': normalizedEmail,
    };
    final absentDates = <DateTime>{};
    final legacyLeaveDates = <DateTime>{};
    final seenDays = <String>{};
    for (final att in records) {
      if (!WorkerIdentity.recordsMatch(att, workerIdentity, allowName: false)) {
        continue;
      }
      final date = AppDateUtils.attendanceRecordDate(att);
      if (date == null) continue;

      final normDate = DateTime(date.year, date.month, date.day);
      final today = DateTime.now();
      final normToday = DateTime(today.year, today.month, today.day);
      if (normDate.isAfter(normToday)) continue;

      if (startDate != null && endDate != null) {
        final normStart = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        );
        final normEnd = DateTime(endDate.year, endDate.month, endDate.day);
        if (normDate.isBefore(normStart) || !normDate.isBefore(normEnd)) {
          continue;
        }
      } else {
        if (date.year != targetMonth.year || date.month != targetMonth.month) {
          continue;
        }
      }
      final identityKey = normalizedWorkerId.isNotEmpty
          ? normalizedWorkerId
          : normalizedEmail;
      final dayKey = '$identityKey-${date.year}-${date.month}-${date.day}';
      if (seenDays.contains(dayKey)) continue;
      seenDays.add(dayKey);
      final status = (att['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'absent') {
        absentDates.add(normDate);
      } else if (status == 'leave') {
        legacyLeaveDates.add(normDate);
      }
    }

    final List<Map<String, dynamic>> timeOffRecords;
    if (preFetchedTimeOffRecords != null) {
      timeOffRecords = preFetchedTimeOffRecords;
    } else if (isGuest) {
      timeOffRecords = List<Map<String, dynamic>>.from(DummyData.timeoff);
    } else {
      final coll = _timeoff;
      if (coll == null) {
        timeOffRecords = const [];
      } else {
        final snapshot = await coll.get();
        timeOffRecords = firestoreRecords(snapshot);
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
      startDate: startDate,
      endDate: endDate,
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

    final Set<DateTime> holidayDates;
    if (preFetchedHolidayDates != null) {
      holidayDates = preFetchedHolidayDates;
    } else if (startDate != null && endDate != null) {
      holidayDates = await _getHolidayDatesForRange(startDate, endDate);
    } else {
      final start = DateTime(targetMonth.year, targetMonth.month, 1);
      final end = DateTime(targetMonth.year, targetMonth.month + 1, 0);
      holidayDates = await _getHolidayDatesForRange(start, end);
    }
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

  Future<int> getMonthlyWorkingDays({
    DateTime? month,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final DateTime fromDate;
    final DateTime toDateExclusive;
    if (startDate != null && endDate != null) {
      fromDate = DateTime(startDate.year, startDate.month, startDate.day);
      toDateExclusive = DateTime(endDate.year, endDate.month, endDate.day);
    } else {
      final now = month ?? DateTime.now();
      fromDate = DateTime(now.year, now.month, 1);
      toDateExclusive = DateTime(now.year, now.month + 1, 1);
    }
    final workingDates = await getWorkingDates(
      from: fromDate,
      toExclusive: toDateExclusive,
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
        for (final date in _calendarDates(start, end))
          if (companyWorkingDays.contains(date.weekday)) date,
      };
    }
    try {
      final snap = await coll.get();
      final calendar = splitCompanyCalendarRecords(
        firestoreRecords(snap),
        fallbackWorkingDays: companyWorkingDays,
      );
      companyWorkingDays = calendar.workingDays;

      final workingDates = <DateTime>{
        for (final date in _calendarDates(start, end))
          if (companyWorkingDays.contains(date.weekday)) date,
      };
      final holidayDates = _holidayDatesFromRecords(
        calendar.holidays,
        start: start,
        end: end,
        allowedDates: workingDates,
      );
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

  static Iterable<DateTime> _calendarDates(DateTime start, DateTime end) sync* {
    for (
      var date = start;
      date.isBefore(end);
      date = date.add(const Duration(days: 1))
    ) {
      yield date;
    }
  }

  static Set<DateTime> _holidayDatesFromRecords(
    Iterable<Map<String, dynamic>> records, {
    required DateTime start,
    required DateTime end,
    Set<DateTime>? allowedDates,
  }) {
    final dates = <DateTime>{};
    for (final record in records) {
      if (record['type'] == 'company_work_days' ||
          record['isEnabled'] == false) {
        continue;
      }
      for (final date in _calendarDates(start, end)) {
        final holidayDate = AppDateUtils.holidayRecordDate(
          record,
          fallbackYear: date.year,
        );
        if (holidayDate != null &&
            holidayDate.month == date.month &&
            holidayDate.day == date.day &&
            _holidayAppliesToYear(record, date.year)) {
          if (allowedDates == null || allowedDates.contains(date)) {
            dates.add(date);
          }
          break;
        }
      }
    }
    return dates;
  }

  Future<Set<DateTime>> _getHolidayDatesForRange(
    DateTime from,
    DateTime to,
  ) async {
    final dates = <DateTime>{};
    final coll = _holidays;
    if (coll == null) return dates;
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    try {
      final snap = await coll.get();
      dates.addAll(
        _holidayDatesFromRecords(
          firestoreRecords(snap),
          start: start,
          end: end,
        ),
      );
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'GetHolidayDatesForRange',
      );
      rethrow;
    }
    return dates;
  }

  Stream<QuerySnapshot> get attendanceStream {
    final coll = _attendance;
    if (coll == null) return const Stream.empty();
    return coll.snapshots();
  }

  Stream<QuerySnapshot> attendanceStreamForWorker(String workerId) {
    final coll = _attendance;
    if (coll == null) return const Stream.empty();
    return coll.where('workerId', isEqualTo: workerId.trim()).snapshots();
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
        .where('attendanceDate', isLessThan: Timestamp.fromDate(end))
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
        .where('attendanceDate', isLessThan: Timestamp.fromDate(end))
        .get();
  }

  /// Fetches all time-off records once, so callers can share them across many
  /// workers instead of re-querying the collection for each worker.
  Future<List<Map<String, dynamic>>> getTimeOffRecords() async {
    final coll = _timeoff;
    if (coll == null) return const [];
    final snapshot = await coll.get();
    return firestoreRecords(snapshot);
  }

  /// Fetches holiday dates for a range once, so callers can share them across
  /// many workers instead of re-querying the collection for each worker.
  Future<Set<DateTime>> getHolidayDatesForRange(DateTime from, DateTime to) {
    return _getHolidayDatesForRange(from, to);
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
      unawaited(
        addNotification({
          if (payrollKey.isNotEmpty) 'notificationKey': 'payroll_$payrollKey',
          'type': 'payroll_added',
          'title': 'notif_title_payroll'.tr(namedArgs: {'name': name}),
          'message': amount.isNotEmpty
              ? 'notif_msg_payroll_amount'.tr(
                  namedArgs: {'amount': amount, 'name': name},
                )
              : 'notif_msg_payroll'.tr(namedArgs: {'name': name}),
          'data': {'name': name, 'amount': amount},
        }).catchError((error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollNotification',
          );
        }),
      );
    }
    return docRef.id;
  }

  Future<int> addBulkPayrollRecords(List<Map<String, dynamic>> records) async {
    final coll = _payroll;
    if (coll == null) return 0;
    if (records.isEmpty) return 0;

    final writtenDocRefs = <DocumentReference>[];
    var saved = 0;
    const chunkSize = 450;
    try {
      for (var start = 0; start < records.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, records.length).toInt();
        final chunk = records.sublist(start, end);
        final batch = _firestore.batch();
        final chunkRefs = <DocumentReference>[];
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
          chunkRefs.add(docRef);
        }
        await batch.commit();
        writtenDocRefs.addAll(chunkRefs);
        saved += chunk.length;
      }
    } catch (error) {
      for (var start = 0; start < writtenDocRefs.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, writtenDocRefs.length).toInt();
        final chunk = writtenDocRefs.sublist(start, end);
        final batch = _firestore.batch();
        for (final ref in chunk) {
          batch.delete(ref);
        }
        try {
          await batch.commit();
        } catch (_) {}
      }
      rethrow;
    }
    return saved;
  }

  /// Saves Pay All payroll rows and their linked salary expenses in the same
  /// Firestore batch, cutting the normal flow from two commits down to one.
  Future<int> addBulkPayrollRecordsAndExpenses({
    required List<Map<String, dynamic>> payrollRecords,
    required List<Map<String, dynamic>> expenseRecords,
  }) async {
    final payrollColl = _payroll;
    final expensesColl = _expenses;
    if (payrollColl == null || expensesColl == null) {
      throw StateError('No authenticated user');
    }
    if (payrollRecords.isEmpty) return 0;

    final expenseByPayrollKey = <String, Map<String, dynamic>>{};
    for (final expense in expenseRecords) {
      Validators.validateExpense(expense);
      final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
      if (payrollKey.isEmpty) {
        throw ArgumentError('payrollKey is required for a payroll expense');
      }
      expenseByPayrollKey[payrollKey] = expense;
    }
    for (final record in payrollRecords) {
      Validators.validatePayroll(record);
    }

    // A worker contributes at most two writes. 225 workers stays below
    // Firestore's 500-write batch limit.
    const workersPerBatch = 225;
    final committedRefs = <DocumentReference>[];
    var saved = 0;
    try {
      for (
        var start = 0;
        start < payrollRecords.length;
        start += workersPerBatch
      ) {
        final end = (start + workersPerBatch)
            .clamp(0, payrollRecords.length)
            .toInt();
        final batch = _firestore.batch();
        final chunkRefs = <DocumentReference>[];
        for (final record in payrollRecords.sublist(start, end)) {
          final payrollKey = (record['payrollKey'] ?? '').toString().trim();
          final payrollRef = payrollKey.isEmpty
              ? payrollColl.doc()
              : payrollColl.doc(_payrollDocumentId(payrollKey));
          batch.set(payrollRef, {
            ...record,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          chunkRefs.add(payrollRef);

          final expense = expenseByPayrollKey[payrollKey];
          if (expense != null) {
            final expenseRef = expensesColl.doc(
              _payrollExpenseDocumentId(payrollKey),
            );
            batch.set(expenseRef, {
              ...expense,
              'payrollKey': payrollKey,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            chunkRefs.add(expenseRef);
          }
        }
        await batch.commit();
        committedRefs.addAll(chunkRefs);
        saved += end - start;
      }
    } catch (_) {
      for (var start = 0; start < committedRefs.length; start += 450) {
        final end = (start + 450).clamp(0, committedRefs.length).toInt();
        final rollback = _firestore.batch();
        for (final ref in committedRefs.sublist(start, end)) {
          rollback.delete(ref);
        }
        try {
          await rollback.commit();
        } catch (_) {}
      }
      rethrow;
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
    var batch = _firestore.batch();
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
        batch = _firestore.batch();
      }
    }
    if (count % 500 != 0 && count > 0) await batch.commit();
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

    final batch = _firestore.batch();
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
        if (reference.path != expenseRef.path) batch.delete(reference);
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

    final batch = _firestore.batch();
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
    final batch = _firestore.batch();
    batch.delete(payrollColl.doc(payrollId));

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

  Future<QuerySnapshot> getPayrollOnce() async {
    final coll = _payroll;
    if (coll == null) throw StateError('No authenticated user');
    return coll.orderBy('createdAt', descending: true).get();
  }

  /// Reads only the payroll rows relevant to the current Pay All selection.
  /// This avoids downloading the company's entire payroll history before each
  /// run while preserving the paid-record recheck immediately before commit.
  Future<List<Map<String, dynamic>>> getPayrollRecordsByKeys(
    Iterable<String> payrollKeys,
  ) async {
    final coll = _payroll;
    if (coll == null) throw StateError('No authenticated user');
    final keys = payrollKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (keys.isEmpty) return const <Map<String, dynamic>>[];

    const queryChunkSize = 30;
    final queries = <Future<QuerySnapshot>>[];
    for (var start = 0; start < keys.length; start += queryChunkSize) {
      final end = (start + queryChunkSize).clamp(0, keys.length).toInt();
      queries.add(
        coll.where('payrollKey', whereIn: keys.sublist(start, end)).get(),
      );
    }

    final snapshots = await Future.wait(queries);
    return <Map<String, dynamic>>[
      for (final snapshot in snapshots)
        for (final document in snapshot.docs)
          {...document.data() as Map<String, dynamic>, 'id': document.id},
    ];
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
      unawaited(
        addNotification({
          'type': 'time_off_added',
          'title': 'notif_title_time_off'.tr(namedArgs: {'name': name}),
          'message': 'notif_msg_time_off'.tr(
            namedArgs: {'type': type, 'name': name},
          ),
          'data': {'name': name, 'type': type},
        }).catchError((error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'TimeOffNotification',
          );
        }),
      );
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
    Map<String, dynamic>? fallbackRecord,
  }) async {
    final timeOffColl = _timeoff;
    final workersColl = _workers;
    if (timeOffColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }

    final timeOffRef = timeOffColl.doc(timeOffId);
    final workerRef = workersColl.doc(workerId);
    final currentTimeOffSnapshot = await timeOffColl.get();
    final currentTimeOffRecords = firestoreRecords(currentTimeOffSnapshot);

    await _firestore.runTransaction((transaction) async {
      final timeOffSnapshot = await transaction.get(timeOffRef);
      final isMissingDocument = !timeOffSnapshot.exists;

      Map<String, dynamic> timeOffData;
      if (isMissingDocument) {
        if (fallbackRecord == null) {
          throw StateError('Time off record does not exist');
        }
        timeOffData = fallbackRecord;
      } else {
        timeOffData = (timeOffSnapshot.data() as Map<String, dynamic>?) ?? {};
        if (!TimeOffService.isActiveRecord(timeOffData)) return;
      }
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
          if (isMissingDocument) {
            dateLocks.remove(key);
          } else if (dateLocks[key]?.toString() == timeOffId) {
            dateLocks.remove(key);
          }
        }

        final recordsAfterCancellation = currentTimeOffRecords
            .where((record) => record['id']?.toString() != timeOffId)
            .map(Map<String, dynamic>.from)
            .toList();
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

      if (!isMissingDocument) {
        transaction.delete(timeOffRef);
      }
      if (workerBalanceUpdate != null) {
        transaction.update(workerRef, workerBalanceUpdate);
      }

      final today = DateTime.now();
      final normalizedToday = DateTime(today.year, today.month, today.day);
      for (final entry in attendanceSnapshots.entries) {
        final snapshot = entry.value;
        if (!snapshot.exists) continue;

        final attendanceDate = AppDateUtils.dateFromValue(entry.key);
        if (attendanceDate != null && attendanceDate.isAfter(normalizedToday)) {
          continue;
        }

        final attendance =
            (snapshot.data() as Map<String, dynamic>?) ?? const {};
        final source = (attendance['source'] ?? '').toString();
        final linkedId = (attendance['timeOffId'] ?? '').toString().trim();
        final isLinkedToThisTimeOff = linkedId == timeOffId;

        if (source == 'auto_leave' &&
            (linkedId.isEmpty || isLinkedToThisTimeOff)) {
          transaction.delete(snapshot.reference);
          continue;
        }

        final status = (attendance['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final attendanceShowsLeave =
            {'leave', 'onleave', 'on leave', 'l'}.contains(status) ||
            source == 'auto_leave';

        final shouldClearLeave =
            isLinkedToThisTimeOff ||
            (isMissingDocument && attendanceShowsLeave);
        if (!shouldClearLeave) continue;

        transaction.delete(snapshot.reference);
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
    if (leaveField.isEmpty) throw StateError('Invalid leave type: $leaveType');

    final docId = isNew
        ? '${workerId.replaceAll(RegExp(r'\s+'), '')}_${DateTime.now().millisecondsSinceEpoch}'
        : timeOffId;
    final timeOffRef = timeOffColl.doc(docId);
    final workerRef = workersColl.doc(workerId);
    final newDates = TimeOffService.selectedDatesForRecord(record);
    if (newDates.isEmpty || requestedDays != newDates.length) {
      throw ArgumentError('requestedDays must match the selected leave dates');
    }
    final currentTimeOffSnapshot = await timeOffColl
        .where('workerId', isEqualTo: workerId)
        .get();
    final currentTimeOffRecords = firestoreRecords(currentTimeOffSnapshot);

    await _firestore.runTransaction((transaction) async {
      final workerSnapshot = await transaction.get(workerRef);
      if (!workerSnapshot.exists) throw StateError('Worker does not exist');

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
            onError: (Object error, StackTrace stackTrace) =>
                ErrorReporter.report(
                  error,
                  stackTrace,
                  context: 'TimeOffBalanceNotification',
                ),
          ),
        );
      }
    }
    return timeOffRef.id;
  }

  Future<void> saveMultipleTimeOffWithWorkerBalance({
    required String workerId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    if (items.length == 1) {
      final item = items.first;
      await saveTimeOffWithWorkerBalance(
        timeOffId: item['timeOffId'] as String?,
        record: item['record'] as Map<String, dynamic>,
        workerId: workerId,
        leaveType: item['leaveType'] as String,
        requestedDays: item['requestedDays'] as int,
      );
      return;
    }

    final timeOffColl = _timeoff;
    final workersColl = _workers;
    if (timeOffColl == null || workersColl == null) {
      throw StateError('No authenticated user');
    }

    final workerRef = workersColl.doc(workerId);
    final currentTimeOffSnapshot = await timeOffColl
        .where('workerId', isEqualTo: workerId)
        .get();
    final currentTimeOffRecords = firestoreRecords(currentTimeOffSnapshot);

    final preparedItems = <Map<String, dynamic>>[];
    final allDatesList = <DateTime>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final timeOffId = item['timeOffId'] as String?;
      final record = item['record'] as Map<String, dynamic>;
      final leaveType = item['leaveType'] as String;
      final requestedDays = item['requestedDays'] as int;

      Validators.validateTimeOff(record);
      final isNew = timeOffId == null || timeOffId.isEmpty;
      final docId = isNew
          ? '${workerId.replaceAll(RegExp(r'\s+'), '')}_${DateTime.now().millisecondsSinceEpoch}_$i'
          : timeOffId;
      final newDates = TimeOffService.selectedDatesForRecord(record);
      if (newDates.isEmpty || requestedDays != newDates.length) {
        throw ArgumentError(
          'requestedDays must match the selected leave dates',
        );
      }

      preparedItems.add({
        'docId': docId,
        'isNew': isNew,
        'record': record,
        'leaveType': leaveType,
        'requestedDays': requestedDays,
        'newDates': newDates,
        'ref': timeOffColl.doc(docId),
      });

      allDatesList.addAll(newDates);
    }

    await _firestore.runTransaction((transaction) async {
      final workerSnapshot = await transaction.get(workerRef);
      if (!workerSnapshot.exists) throw StateError('Worker does not exist');

      final workerData = (workerSnapshot.data() as Map<String, dynamic>?) ?? {};
      final workerWithId = {
        ...workerData,
        'id': workerId,
        'workerId': workerId,
      };

      final dateLocks = workerData['timeOffDateLocks'] is Map
          ? Map<String, dynamic>.from(workerData['timeOffDateLocks'] as Map)
          : <String, dynamic>{};

      for (final item in preparedItems) {
        final isNew = item['isNew'] as bool;
        final docId = item['docId'] as String;
        final newDates = item['newDates'] as List<DateTime>;
        final ref = item['ref'] as DocumentReference;
        final leaveType = item['leaveType'] as String;

        if (!isNew) {
          final existingRecordSnapshot = await transaction.get(ref);
          if (!existingRecordSnapshot.exists) {
            throw StateError('Time off record does not exist');
          }
          final oldRecordData =
              (existingRecordSnapshot.data() as Map<String, dynamic>?) ?? {};
          final oldDates = TimeOffService.selectedDatesForRecord(oldRecordData);
          if (TimeOffService.hasPastDateModification(
            oldDates: oldDates,
            newDates: newDates,
          )) {
            throw const PastTimeOffEditException();
          }
          final oldWorkerId = (oldRecordData['workerId'] ?? '')
              .toString()
              .trim();
          if (oldWorkerId.isNotEmpty && oldWorkerId != workerId) {
            throw StateError(
              'The worker on an existing time off cannot change',
            );
          }
          if (!TimeOffService.recordHasLeaveType(oldRecordData, leaveType)) {
            throw StateError(
              'An existing time off record cannot be changed to another leave type',
            );
          }
          for (final date in oldDates) {
            final key = _timeOffDateKey(date);
            if (dateLocks[key]?.toString() == docId) dateLocks.remove(key);
          }
        }
      }

      final batchClaimedLocks = <String, String>{};
      for (final item in preparedItems) {
        final docId = item['docId'] as String;
        final newDates = item['newDates'] as List<DateTime>;
        for (final date in newDates) {
          final key = _timeOffDateKey(date);
          final owner = (dateLocks[key] ?? '').toString().trim();
          if (owner.isNotEmpty && owner != docId) {
            throw const DuplicateTimeOffDateException();
          }
          if (batchClaimedLocks.containsKey(key)) {
            throw const DuplicateTimeOffDateException();
          }
          batchClaimedLocks[key] = docId;
        }
      }
      dateLocks.addAll(batchClaimedLocks);

      final simulatedRecords = currentTimeOffRecords
          .where(
            (r) =>
                !preparedItems.any((pi) => pi['docId'] == r['id']?.toString()),
          )
          .map(Map<String, dynamic>.from)
          .toList();

      for (final item in preparedItems) {
        final docId = item['docId'] as String;
        final record = item['record'] as Map<String, dynamic>;
        final newDates = item['newDates'] as List<DateTime>;
        final isNew = item['isNew'] as bool;

        if (TimeOffService.hasOverlappingApprovedLeave(
          workerWithId,
          simulatedRecords,
          newDates,
          excludingRecordId: isNew ? null : docId,
        )) {
          throw const DuplicateTimeOffDateException();
        }
        simulatedRecords.add({...record, 'id': docId});
      }

      final remainingBalances =
          TimeOffService.remainingBalancesFromAssignedRecords(
            workerWithId,
            simulatedRecords,
          );

      for (final item in preparedItems) {
        final leaveType = item['leaveType'] as String;
        final key = switch (TimeOffService.normalizeLeaveType(leaveType)) {
          'Annual Leave' => 'annualLeave',
          'Sick Leave' => 'sickLeave',
          'Casual Leave' => 'casualLeave',
          'Medical Leave' => 'medicalLeave',
          _ => '',
        };
        if (key.isNotEmpty && (remainingBalances[key] ?? 0) < 0) {
          throw StateError('Insufficient $leaveType balance');
        }
      }

      final attendanceSnapshots = <String, DocumentSnapshot>{};
      final attendanceColl = _attendance;
      if (attendanceColl != null && allDatesList.isNotEmpty) {
        final snapshots = await Future.wait(
          allDatesList.map(
            (d) => transaction.get(
              attendanceColl.doc(_attendanceDocumentId(workerId, d)),
            ),
          ),
        );
        for (int i = 0; i < allDatesList.length; i++) {
          attendanceSnapshots[_timeOffDateKey(allDatesList[i])] = snapshots[i];
        }
      }

      final workerUpdates = TimeOffService.canonicalWorkerLeaveFields(
        workerWithId,
        remainingBalances: remainingBalances,
      )..['timeOffDateLocks'] = dateLocks;
      transaction.update(workerRef, workerUpdates);

      for (final item in preparedItems) {
        final isNew = item['isNew'] as bool;
        final record = item['record'] as Map<String, dynamic>;
        final ref = item['ref'] as DocumentReference;
        transaction.set(ref, {
          ...record,
          if (isNew) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      for (final entry in attendanceSnapshots.entries) {
        final snapshot = entry.value;
        if (!snapshot.exists) continue;
        final dateKey = entry.key;
        final matchingItem = preparedItems.firstWhere(
          (pi) => (pi['newDates'] as List<DateTime>).any(
            (d) => _timeOffDateKey(d) == dateKey,
          ),
          orElse: () => preparedItems.first,
        );
        final docId = matchingItem['docId'] as String;
        final leaveType = matchingItem['leaveType'] as String;

        final attendance =
            (snapshot.data() as Map<String, dynamic>?) ?? const {};
        final source = (attendance['source'] ?? '').toString();
        final linkedId = (attendance['timeOffId'] ?? '').toString().trim();
        if (source == 'auto_leave' && (linkedId.isEmpty || linkedId == docId)) {
          transaction.set(snapshot.reference, {
            'status': 'Leave',
            'type': TimeOffService.normalizeLeaveType(leaveType),
            'source': 'auto_leave',
            'timeOffId': docId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    });
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
    final batch = _firestore.batch();
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
    if (coll == null || workerId.trim().isEmpty) return const Stream.empty();
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
      unawaited(
        addNotification({
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
        }).catchError((error, stackTrace) {
          ErrorReporter.report(error, stackTrace, context: 'AssetNotification');
        }),
      );
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
    final normalized = validWorkingDays(weekdays).toList()..sort();
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
    final docRef = _firestore.collection('hrms_user').doc(uid);
    final userSnap = await docRef.get();

    if (!force && userSnap.exists) {
      final data = userSnap.data();
      if (data != null && data['hasDummyData'] == true) return;
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

    var batch = _firestore.batch();
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
        batch = _firestore.batch();
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
        batch = _firestore.batch();
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
        batch = _firestore.batch();
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
        batch = _firestore.batch();
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
        batch = _firestore.batch();
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
          batch = _firestore.batch();
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
        batch = _firestore.batch();
      }
    }

    if (count % 500 != 0) await batch.commit();
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
    return _firestore.runTransaction<bool>((transaction) async {
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
    return _firestore.runTransaction<bool>((transaction) async {
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
    return coll.orderBy('createdAt', descending: true).limit(100).snapshots();
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

    var batch = _firestore.batch();
    var pending = 0;
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
      pending++;
      if (pending == 450) {
        await batch.commit();
        batch = _firestore.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
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

  Future<void> markNotificationAsRead(String id) async {
    final coll = _notifications;
    if (coll == null || id.trim().isEmpty) return;
    await coll.doc(id).set({
      'isRead': true,
      'readAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> clearAllNotifications() async {
    final coll = _notifications;
    if (coll == null) return;
    final snap = await coll.get();
    if (snap.docs.isEmpty) return;
    await _deleteDocumentsInChunks(snap.docs.map((doc) => doc.reference));
  }

  Future<List<Map<String, dynamic>>> getPolicies() async => [];
  Future<List<Map<String, dynamic>>> getLeavePolicies() async => [];
}
