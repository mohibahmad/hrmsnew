import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/validators.dart';
import '../utils/worker_identity.dart';
import 'auth_service.dart';
import 'dummy_data.dart';
import 'error_reporter.dart';
import 'time_off_service.dart';
import 'upload_service.dart';
import 'preferences_service.dart';

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

  String _safeDocumentKey(String value) => value.trim().replaceAll('/', '_');

  String _payrollDocumentId(String payrollKey) => _safeDocumentKey(payrollKey);

  String _payrollExpenseDocumentId(String payrollKey) =>
      'salary_${_safeDocumentKey(payrollKey)}';

  String _payrollNotificationDocumentId(String payrollKey) =>
      _safeDocumentKey('payroll_${payrollKey.trim()}');

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
    if (coll == null)
      return BulkWorkerResult(imported: 0, skipped: workersList.length);

    final existingSnapshot = await coll.get();
    final existingWorkers = existingSnapshot.docs
        .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
        .toList();

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
        final duplicateField = WorkerIdentity.duplicateField(worker, [
          ...existingWorkers,
          ...acceptedWorkers,
        ]);
        if (duplicateField != null) {
          skipped++;
          if (clientRowId.isNotEmpty) skippedClientRowIds.add(clientRowId);
          skipReasons.add(
            'Duplicate ${duplicateField.name}: ${worker['name'] ?? worker['email'] ?? ''}',
          );
          continue;
        }
        acceptedWorkers.add(worker);
        validWorkers.add(worker);
      } catch (e) {
        skipped++;
        if (clientRowId.isNotEmpty) skippedClientRowIds.add(clientRowId);
        final errorText = e.toString();
        final safeError = errorText.length <= 100
            ? errorText
            : errorText.substring(0, 100);
        skipReasons.add('Validation error: $safeError');
        continue;
      }
    }

    int count = 0;
    if (validWorkers.isNotEmpty) {
      const batchSize = 500;
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
    var batch = _db.batch();
    int count = 0;
    for (final worker in workers) {
      final docRef = coll.doc();
      batch.set(docRef, {
        ..._withNormalizedCurrency(worker),
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
    await coll.doc(id).update({
      ..._withNormalizedCurrency(data),
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
    await coll.doc(id).update(leaveData);
  }

  
  
  
  
  Future<void> updateWorkerFields(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final coll = _workers;
    if (coll == null || id.isEmpty) return;
    await coll.doc(id).set(
      {
        ..._withNormalizedCurrency(fields),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

      final usedPaidDays = TimeOffService.paidDaysUsedForWorker(
        worker,
        workerRecords,
      );
      final remaining = (annualLeaveDays - usedPaidDays).clamp(
        0,
        annualLeaveDays,
      );

      batch.update(coll.doc(workerId), {
        'annualLeaves': annualLeaveDays,
        'sickLeaves': sickLeaveDays,
        'casualLeaves': casualLeaveDays,
        'medicalLeaves': medicalLeaveDays,
        'availableAnnualLeaves': remaining,
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
        final annual = int.tryParse(policyData['annualLeaveDays']?.toString() ?? '14') ?? 14;
        final sick = int.tryParse(policyData['sickLeaves']?.toString() ?? '5') ?? 5;
        final casual = int.tryParse(policyData['casualLeaves']?.toString() ?? '5') ?? 5;
        final medical = int.tryParse(policyData['medicalLeaves']?.toString() ?? '5') ?? 5;
        updates['annualLeaves'] = annual;
        updates['sickLeaves'] = sick;
        updates['casualLeaves'] = casual;
        updates['medicalLeaves'] = medical;
        updates['leavePolicy'] = policyName;
      } else if (policyType == 'Payroll Policy') {
        updates['paymentFrequency'] = policyData['paymentFrequency'] ?? 'Monthly';
        updates['taxRatePercent'] = double.tryParse(policyData['taxRatePercent']?.toString() ?? '5.0') ?? 5.0;
        updates['salaryDay'] = int.tryParse(policyData['salaryDay']?.toString() ?? '1') ?? 1;
        updates['payrollPolicy'] = policyName;
      } else if (policyType == 'Holiday Policy') {
        updates['weeklyOffDays'] = policyData['weeklyOffDays'] ?? 'Sunday';
        updates['paidHolidaysCount'] = int.tryParse(policyData['paidHolidaysCount']?.toString() ?? '10') ?? 10;
        updates['holidayPolicy'] = policyName;
      } else if (policyType == 'Asset Policy') {
        updates['maxAssetsPerWorker'] = int.tryParse(policyData['maxAssetsPerWorker']?.toString() ?? '3') ?? 3;
        updates['returnGracePeriodDays'] = int.tryParse(policyData['returnGracePeriodDays']?.toString() ?? '7') ?? 7;
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
    return coll.orderBy('createdAt', descending: true).snapshots();
  }

  Future<QuerySnapshot> getWorkersOnce() async {
    final coll = _workers;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.get();
  }

  /// Finds which identity field (email or national ID) already exists on
  /// another worker, using the same normalization rules enforced on save.
  /// Returns null when no duplicate is found.
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
        if (email != null) 'email': email,
        if (nationalId != null) 'nationalId': nationalId,
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
                  'amount': '${CurrencyUtils.symbolFor(PreferencesService.cachedCompanyCurrency)}$amount'
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
    final workerId = (record['workerId'] ?? '').toString().trim();
    final attendanceDate = AppDateUtils.dateFromValue(
      record['attendanceDate'] ?? record['date'],
    );
    final now = attendanceDate ?? DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final docRef = workerId.isNotEmpty
        ? coll.doc('${workerId}_$dateKey')
        : coll.doc();
    await docRef.set({
      ...record,
      'attendanceDate': Timestamp.fromDate(
        DateTime(now.year, now.month, now.day),
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });
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
    bool deleteTimeOff = false,
    String? workerId,
    Map<String, dynamic>? balance,
  }) async {
    Validators.validateAttendance(attendanceRecord);
    if (timeOffRecord != null) Validators.validateTimeOff(timeOffRecord);
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
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final isNewAttendance = attendanceId == null || attendanceId.trim().isEmpty;
    final attendanceRef = isNewAttendance
        ? (normalizedWorkerId.isNotEmpty
              ? attendanceColl.doc('${normalizedWorkerId}_$dateKey')
              : attendanceColl.doc())
        : attendanceColl.doc(attendanceId.trim());

    batch.set(attendanceRef, {
      ...attendanceRecord,
      'attendanceDate': Timestamp.fromDate(
        DateTime(now.year, now.month, now.day),
      ),
      if (isNewAttendance) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final timeOffColl = _timeoff;
    final existingTimeOffId = (timeOffId ?? '').trim();
    String savedTimeOffId = existingTimeOffId;
    if (timeOffColl != null &&
        (timeOffRecord != null ||
            (deleteTimeOff && existingTimeOffId.isNotEmpty))) {
      final isNewTimeOff = existingTimeOffId.isEmpty;
      final timeOffRef = isNewTimeOff
          ? timeOffColl.doc()
          : timeOffColl.doc(existingTimeOffId);
      if (timeOffRecord != null) {
        batch.set(timeOffRef, {
          ...timeOffRecord,
          if (isNewTimeOff) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        savedTimeOffId = timeOffRef.id;
      } else {
        batch.delete(timeOffRef);
      }
    }

    if (normalizedWorkerId.isNotEmpty &&
        balance != null &&
        balance.isNotEmpty) {
      batch.set(
        workersColl.doc(normalizedWorkerId),
        balance,
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

  Future<Map<String, int>> getWorkerMonthlyAttendance(
    String email, {
    String? workerId,
    DateTime? month,
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
    } else {
      final coll = _attendance;
      if (coll == null) return {'absents': 0, 'leaves': 0};

      final startOfMonth = DateTime(targetMonth.year, targetMonth.month, 1);
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
      records = recordsById.values.toList();
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
      final identityMatches =
          normalizedWorkerId.isNotEmpty && attendanceWorkerId.isNotEmpty
          ? normalizedWorkerId == attendanceWorkerId
          : normalizedEmail.isNotEmpty && attEmail == normalizedEmail;
      if (!identityMatches) continue;
      final date = AppDateUtils.attendanceRecordDate(att);
      if (date == null) continue;
      if (date.year != targetMonth.year || date.month != targetMonth.month) {
        continue;
      }
      final identityKey = attendanceWorkerId.isNotEmpty
          ? attendanceWorkerId
          : attEmail;
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
        final hDay = int.tryParse((data['day'] ?? '').toString());
        final hMonthStr = (data['month'] ?? '').toString();
        final hMonth = _parseMonthString(hMonthStr);
        if (hDay == null || hDay < 1 || hDay > 31) continue;
        for (
          var date = start;
          date.isBefore(end);
          date = date.add(const Duration(days: 1))
        ) {
          if (hMonth == date.month &&
              hDay == date.day &&
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
    final rawYear = holiday['year'];
    final holidayYear = rawYear is num
        ? rawYear.toInt()
        : int.tryParse((rawYear ?? '').toString());

    return holidayYear == null || holidayYear == year;
  }

  static int _parseMonthString(String month) {
    const months = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
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
        if (data['type'] == 'company_work_days') continue;
        if (data['isEnabled'] == false) continue;
        final hDay = int.tryParse((data['day'] ?? '').toString());
        final hMonth = _parseMonthString((data['month'] ?? '').toString());
        if (_holidayAppliesToYear(data, year) &&
            hMonth == month &&
            hDay != null &&
            hDay >= 1 &&
            hDay <= 31) {
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

    var saved = 0;

    const chunkSize = 50;
    for (var start = 0; start < records.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, records.length).toInt();
      final chunk = records.sublist(start, end);

      final results = await Future.wait(
        chunk.map((record) async {
          try {
            Validators.validatePayroll(record);
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
            return true;
          } catch (_) {
            return false;
          }
        }),
      );

      saved += results.where((result) => result).length;
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

  Future<void> updatePayrollByPayrollKey(String payrollKey, Map<String, dynamic> data) async {
    final coll = _payroll;
    if (coll == null || payrollKey.trim().isEmpty) return;

    final snapshot = await coll.where('payrollKey', isEqualTo: payrollKey.trim()).limit(1).get();
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
      final existingExpenses = await _expenses!
          .where('payrollKey', isEqualTo: normalizedPayrollKey)
          .get();

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

      for (final doc in existingExpenses.docs) {
        if (doc.reference.path != expenseRef.path) {
          batch.delete(doc.reference);
        }
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
    for (final expense in expenseDocs) {
      batch.delete(expense.reference);
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

    await _db.runTransaction((transaction) async {
      final timeOffSnapshot = await transaction.get(timeOffRef);
      if (!timeOffSnapshot.exists) {
        throw StateError('Time off record does not exist');
      }
      final timeOffData = (timeOffSnapshot.data() as Map<String, dynamic>?) ?? {};
      final String leaveType = (timeOffData['action'] ?? timeOffData['type'] ?? '').toString();
      final int requestedDays = int.tryParse(timeOffData['requestedDays']?.toString() ?? '0') ?? 0;

      final leaveField = switch (TimeOffService.normalizeLeaveType(leaveType)) {
        'Annual Leave' => 'annualLeave',
        'Sick Leave' => 'sickLeave',
        'Casual Leave' => 'casualLeave',
        'Medical Leave' => 'medicalLeave',
        _ => '',
      };

      transaction.update(timeOffRef, {
        'status': 'Cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (leaveField.isNotEmpty && requestedDays > 0) {
        final workerSnapshot = await transaction.get(workerRef);
        if (workerSnapshot.exists) {
          final workerData = (workerSnapshot.data() as Map<String, dynamic>?) ?? {};
          int currentBalance = 0;
          final leaveBalances = workerData['leaveBalances'] as Map<String, dynamic>?;
          if (leaveBalances != null && leaveBalances.containsKey(leaveField)) {
            currentBalance = int.tryParse(leaveBalances[leaveField]?.toString() ?? '0') ?? 0;
          } else {
            currentBalance = switch (leaveField) {
              'annualLeave' => int.tryParse((workerData['availableAnnualLeaves'] ?? workerData['annualLeaves'] ?? '0').toString()) ?? 0,
              'sickLeave' => int.tryParse((workerData['sickLeaves'] ?? '0').toString()) ?? 0,
              'casualLeave' => int.tryParse((workerData['casualLeaves'] ?? '0').toString()) ?? 0,
              'medicalLeave' => int.tryParse((workerData['medicalLeaves'] ?? '0').toString()) ?? 0,
              _ => 0,
            };
          }

          final newBalance = currentBalance + requestedDays;

          transaction.update(workerRef, {
            'leaveBalances.$leaveField': newBalance,
            if (leaveField == 'annualLeave') 'availableAnnualLeaves': newBalance.toString(),
          });
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
    await _db.runTransaction((transaction) async {
      final workerSnapshot = await transaction.get(workerRef);
      if (!workerSnapshot.exists) {
        throw StateError('Worker does not exist');
      }

      final workerData = (workerSnapshot.data() as Map<String, dynamic>?) ?? {};

      String? oldLeaveField;
      int oldDays = 0;
      if (!isNew) {
        final existingRecordSnapshot = await transaction.get(timeOffRef);
        if (existingRecordSnapshot.exists) {
          final oldRecordData = (existingRecordSnapshot.data() as Map<String, dynamic>?) ?? {};
          final oldType = oldRecordData['action'] ?? oldRecordData['type'] ?? leaveType;
          oldLeaveField = switch (TimeOffService.normalizeLeaveType(oldType.toString())) {
            'Annual Leave' => 'annualLeave',
            'Sick Leave' => 'sickLeave',
            'Casual Leave' => 'casualLeave',
            'Medical Leave' => 'medicalLeave',
            _ => null,
          };
          oldDays = TimeOffService.selectedDatesForRecord(oldRecordData).length;
          if (oldDays == 0) {
            oldDays = int.tryParse(oldRecordData['requestedDays']?.toString() ?? '0') ?? 0;
          }
        }
      }

      final Map<String, dynamic> leaveBalances = Map<String, dynamic>.from(
        (workerData['leaveBalances'] as Map<String, dynamic>?) ?? {},
      );

      int getFieldBalance(String field) {
        if (leaveBalances.containsKey(field)) {
          return int.tryParse(leaveBalances[field]?.toString() ?? '0') ?? 0;
        }
        return switch (field) {
          'annualLeave' => int.tryParse((workerData['availableAnnualLeaves'] ?? workerData['annualLeaves'] ?? '0').toString()) ?? 0,
          'sickLeave' => int.tryParse((workerData['sickLeaves'] ?? '0').toString()) ?? 0,
          'casualLeave' => int.tryParse((workerData['casualLeaves'] ?? '0').toString()) ?? 0,
          'medicalLeave' => int.tryParse((workerData['medicalLeaves'] ?? '0').toString()) ?? 0,
          _ => 0,
        };
      }

      if (oldLeaveField != null && oldDays > 0) {
        final currentOldVal = getFieldBalance(oldLeaveField);
        leaveBalances[oldLeaveField] = currentOldVal + oldDays;
      }

      final currentNewVal = getFieldBalance(leaveField);
      final updatedNewVal = (currentNewVal - requestedDays).clamp(0, 9999);
      leaveBalances[leaveField] = updatedNewVal;

      final Map<String, dynamic> workerUpdates = {
        'leaveBalances': leaveBalances,
      };
      if (leaveBalances.containsKey('annualLeave')) {
        workerUpdates['availableAnnualLeaves'] = leaveBalances['annualLeave'].toString();
      }

      transaction.update(workerRef, workerUpdates);

      transaction.set(timeOffRef, {
        ...record,
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (isNew) {
      final name = (record['workerName'] ?? record['name'] ?? '').toString();
      final type = (record['type'] ?? record['leaveType'] ?? 'Leave')
          .toString();
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
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'TimeOffBalanceNotification',
          );
        }
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

  Future<QuerySnapshot> getTimeoffForWorker(String workerId) async {
    final coll = _timeoff;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.where('workerId', isEqualTo: workerId).get();
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

  Future<QuerySnapshot> getAssetsOnce({int limit = 50}) async {
    final coll = _assets;
    if (coll == null) throw StateError('No authenticated user');
    return await coll.orderBy('createdAt', descending: true).limit(limit).get();
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
      try {
        await addNotification({
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
