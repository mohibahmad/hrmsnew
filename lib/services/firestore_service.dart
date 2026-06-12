import 'package:cloud_firestore/cloud_firestore.dart';
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
    await _userDoc.update(data);
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

    final batch = _db.batch();

    for (final collectionName in [
      'hrms_workers',
      'hrms_expenses',
      'hrms_attendance',
      'hrms_payroll',
      'hrms_timeoff',
    ]) {
      final snapshot = await _userDoc.collection(collectionName).get();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    batch.update(_userDoc, {'hasDummyData': false});
    await batch.commit();
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
    final docRef = await _workers.add({
      ...worker,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateWorker(String id, Map<String, dynamic> data) async {
    await _workers.doc(id).update(data);
  }

  Future<void> deleteWorker(String id) async {
    await _workers.doc(id).delete();
  }

  Stream<QuerySnapshot> get workersStream =>
      _workers.orderBy('createdAt', descending: true).snapshots();

  Future<String> addExpense(Map<String, dynamic> expense) async {
    final docRef = await _expenses.add({
      ...expense,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> deleteExpense(String id) async {
    await _expenses.doc(id).delete();
  }

  Stream<QuerySnapshot> get expensesStream =>
      _expenses.orderBy('createdAt', descending: true).snapshots();

  Future<String> addAttendanceRecord(Map<String, dynamic> record) async {
    final docRef = await _attendance.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> deleteAttendanceRecord(String id) async {
    await _attendance.doc(id).delete();
  }

  Stream<QuerySnapshot> get attendanceStream =>
      _attendance.orderBy('createdAt', descending: true).snapshots();

  Future<String> addPayrollRecord(Map<String, dynamic> record) async {
    final docRef = await _payroll.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> deletePayrollRecord(String id) async {
    await _payroll.doc(id).delete();
  }

  Stream<QuerySnapshot> get payrollStream =>
      _payroll.orderBy('createdAt', descending: true).snapshots();

  Future<String> addTimeOffRecord(Map<String, dynamic> record) async {
    final docRef = await _timeoff.add({
      ...record,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> deleteTimeOffRecord(String id) async {
    await _timeoff.doc(id).delete();
  }

  Stream<QuerySnapshot> get timeoffStream =>
      _timeoff.orderBy('createdAt', descending: true).snapshots();

  Future<void> seedDummyDataForUser({
    required String uid,
    required String displayName,
    required String email,
  }) async {
    final docRef = _db.collection('hrms_user').doc(uid);
    final userSnap = await docRef.get();

    if (userSnap.exists) {
      final data = userSnap.data();
      if (data != null && data['hasDummyData'] == true) {
        return; // Already seeded
      }
    }

    final batch = _db.batch();

    // Create user profile
    batch.set(docRef, {
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

    final workersColl = docRef.collection('hrms_workers');
    final attendanceColl = docRef.collection('hrms_attendance');
    final expensesColl = docRef.collection('hrms_expenses');
    final payrollColl = docRef.collection('hrms_payroll');
    final timeoffColl = docRef.collection('hrms_timeoff');

    // 1. Seed Workers (batch)
    final dummyWorkers = DummyData.workers.map((w) {
      final copy = Map<String, dynamic>.from(w);
      copy.remove('id');
      return copy;
    }).toList();

    for (var w in dummyWorkers) {
      batch.set(workersColl.doc(), {
        ...w,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 2. Seed Attendance
    final dummyAttendance = DummyData.attendance.map((a) {
      final copy = Map<String, dynamic>.from(a);
      copy.remove('id');
      return copy;
    }).toList();

    for (var a in dummyAttendance) {
      await attendanceColl.add({
        ...a,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 3. Seed Expenses
    final dummyExpenses = DummyData.expenses.map((e) {
      final copy = Map<String, dynamic>.from(e);
      copy.remove('id');
      return copy;
    }).toList();

    for (var e in dummyExpenses) {
      await expensesColl.add({...e, 'createdAt': FieldValue.serverTimestamp()});
    }

    // 4. Seed Payroll
    final dummyPayroll = DummyData.payroll.map((p) {
      final copy = Map<String, dynamic>.from(p);
      copy.remove('id');
      return copy;
    }).toList();

    for (var p in dummyPayroll) {
      await payrollColl.add({...p, 'createdAt': FieldValue.serverTimestamp()});
    }

    // 5. Seed Time Off requests
    final dummyTimeoff = DummyData.timeoff.map((t) {
      final copy = Map<String, dynamic>.from(t);
      copy.remove('id');
      return copy;
    }).toList();

    for (var t in dummyTimeoff) {
      await timeoffColl.add({...t, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Future<bool> isUserDeletedByEmail(String email) async {
    final emailVariants = {
      email.trim(),
      email.toLowerCase().trim(),
    }.where((value) => value.isNotEmpty).toList();

    for (final emailToCheck in emailVariants) {
      final snapshot = await _db
          .collection('hrms_user')
          .where('email', isEqualTo: emailToCheck)
          .where('isDeleted', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) return true;
    }

    return false;
  }
}
