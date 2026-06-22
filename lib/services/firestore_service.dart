import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/validators.dart';
import 'auth_service.dart';
import 'dummy_data.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _userKey {
    final email = AuthService().currentUser?.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) return email;
    return AuthService().currentUser?.uid ?? '';
  }

  DocumentReference get _userDoc => _db.collection('hrms_user').doc(_userKey);

  CollectionReference get _workers => _userDoc.collection('hrms_workers');
  CollectionReference get _expenses => _userDoc.collection('hrms_expenses');
  CollectionReference get _attendance => _userDoc.collection('hrms_attendance');
  CollectionReference get _payroll => _userDoc.collection('hrms_payroll');
  CollectionReference get _timeoff => _userDoc.collection('hrms_timeoff');
  CollectionReference get _assets => _userDoc.collection('hrms_assets');
  CollectionReference get _holidays => _userDoc.collection('hrms_holidays');

  Future<void> createUserProfile({
    required String username,
    required String email,
    required String phone,
  }) async {
    await _userDoc.set({
      'username': username,
      'email': email,
      'phone': phone,
      'hasDummyData': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    await _userDoc.set(data, SetOptions(merge: true));
  }

  Future<void> deleteUserData() async {
    if (_userKey.isEmpty) return;
    await _userDoc.set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearDummyDataForCurrentUser() async {
    if (_userKey.isEmpty) return;

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
      final snapshot = await _userDoc.collection(collectionName).get();
      var batch = _db.batch();
      int count = 0;
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
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

    await _userDoc.update({'hasDummyData': false});
  }

  Future<bool> isCurrentUserDeleted() async {
    final profile = await getUserProfile();
    return profile?['isDeleted'] == true;
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    final doc = await _userDoc.get();
    return doc.data() as Map<String, dynamic>?;
  }

  Future<String> addWorker(Map<String, dynamic> worker) async {
    Validators.validateWorker(worker);
    final docRef = await _workers.add({
      ...worker,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> addBulkWorkers(List<Map<String, dynamic>> workersList) async {
    var batch = _db.batch();
    int count = 0;
    
    for (var worker in workersList) {
      try {
        Validators.validateWorker(worker);
        final docRef = _workers.doc();
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
        // Skip invalid rows
        continue;
      }
    }
    
    if (count % 500 != 0 && count > 0) {
      await batch.commit();
    }
  }

  Future<void> updateWorker(String id, Map<String, dynamic> data) async {
    Validators.validateWorker(data);
    await _workers.doc(id).update(data);
  }

  Future<void> deleteWorker(String id) async {
    await _workers.doc(id).delete();
  }

  Stream<QuerySnapshot> get workersStream =>
      _workers.orderBy('createdAt', descending: true).snapshots();

  Future<QuerySnapshot> getWorkersOnce() async {
    return await _workers.get();
  }

  Future<String> addExpense(Map<String, dynamic> expense) async {
    Validators.validateExpense(expense);
    final docRef = await _expenses.add({
      ...expense,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    Validators.validateExpense(data);
    await _expenses.doc(id).update(data);
  }

  Future<void> deleteExpense(String id) async {
    await _expenses.doc(id).delete();
  }

  Stream<QuerySnapshot> get expensesStream =>
      _expenses.orderBy('createdAt', descending: true).snapshots();

  Future<String> addAttendanceRecord(Map<String, dynamic> record) async {
    Validators.validateAttendance(record);
    final docRef = await _attendance.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateAttendanceRecord(String id, Map<String, dynamic> data) async {
    Validators.validateAttendance(data);
    await _attendance.doc(id).update(data);
  }

  Future<void> deleteAttendanceRecord(String id) async {
    await _attendance.doc(id).delete();
  }

  Stream<QuerySnapshot> get attendanceStream =>
      _attendance.orderBy('createdAt', descending: true).snapshots();

  Future<String> addPayrollRecord(Map<String, dynamic> record) async {
    Validators.validatePayroll(record);
    final docRef = await _payroll.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updatePayrollRecord(String id, Map<String, dynamic> data) async {
    await _payroll.doc(id).update(data);
  }

  Future<void> deletePayrollRecord(String id) async {
    await _payroll.doc(id).delete();
  }

  Stream<QuerySnapshot> get payrollStream =>
      _payroll.orderBy('createdAt', descending: true).snapshots();

  Future<String> addTimeOffRecord(Map<String, dynamic> record) async {
    Validators.validateTimeOff(record);
    final docRef = await _timeoff.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateTimeOffRecord(String id, Map<String, dynamic> data) async {
    await _timeoff.doc(id).update(data);
  }

  Future<void> deleteTimeOffRecord(String id) async {
    await _timeoff.doc(id).delete();
  }

  Stream<QuerySnapshot> get timeoffStream =>
      _timeoff.orderBy('createdAt', descending: true).snapshots();

  // --- Assets CRUD ---
  Future<String> addAsset(Map<String, dynamic> asset) async {
    Validators.validateAsset(asset);
    final docRef = await _assets.add({
      ...asset,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateAsset(String id, Map<String, dynamic> data) async {
    Validators.validateAsset(data);
    await _assets.doc(id).update(data);
  }

  Future<void> deleteAsset(String id) async {
    await _assets.doc(id).delete();
  }

  Stream<QuerySnapshot> get assetsStream =>
      _assets.orderBy('createdAt', descending: true).snapshots();

  // --- Holidays CRUD ---
  Future<String> addHoliday(Map<String, dynamic> holiday) async {
    Validators.validateHoliday(holiday);
    final docRef = await _holidays.add({
      ...holiday,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateHoliday(String id, Map<String, dynamic> data) async {
    // Holiday updates are often partial (e.g. toggling `isEnabled`), so we
    // only validate the name when the caller actually sets it.
    if (data.containsKey('name')) Validators.validateHoliday(data);
    await _holidays.doc(id).update(data);
  }

  Future<void> deleteHoliday(String id) async {
    await _holidays.doc(id).delete();
  }

  Stream<QuerySnapshot> get holidaysStream =>
      _holidays.orderBy('createdAt', descending: true).snapshots();


  Future<void> seedDummyDataForUser({
    required String uid,
    required String displayName,
    required String email,
  }) async {
    final userKey = email.trim().toLowerCase().isNotEmpty
        ? email.trim().toLowerCase()
        : uid;
    final docRef = _db.collection('hrms_user').doc(userKey);
    final userSnap = await docRef.get();

    if (userSnap.exists) {
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
      'createdAt': FieldValue.serverTimestamp(),
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
}
