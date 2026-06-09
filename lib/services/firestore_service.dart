import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => AuthService().currentUser?.uid;

  DocumentReference get _userDoc => _db.collection('users').doc(_uid);

  CollectionReference get _workers => _userDoc.collection('workers');
  CollectionReference get _expenses => _userDoc.collection('expenses');
  CollectionReference get _attendance => _userDoc.collection('attendance');
  CollectionReference get _payroll => _userDoc.collection('payroll');
  CollectionReference get _timeoff => _userDoc.collection('timeoff');

  Future<void> createUserProfile({
    required String username,
    required String email,
    required String phone,
  }) async {
    await _userDoc.set({
      'username': username,
      'email': email,
      'phone': phone,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    await _userDoc.update(data);
  }

  Future<void> deleteUserData() async {
    await _userDoc.delete();
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
}
