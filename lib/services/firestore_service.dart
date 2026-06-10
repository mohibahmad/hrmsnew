import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => AuthService().currentUser?.uid;

  DocumentReference get _userDoc => _db.collection('hrms_user').doc(_uid);

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
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (_uid != null) {
      await seedDummyDataForUser(
        uid: _uid!,
        displayName: username,
        email: email,
      );
    }
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    await _userDoc.update(data);
  }

  Future<void> deleteUserData() async {
    if (_uid == null) return;
    await _userDoc.set({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final dummyWorkers = [
      {
        'name': 'John Smith',
        'email': 'john.smith@stark.com',
        'type1': 'Full-Time',
        'position': 'Senior Web Developer',
        'type2': 'Remote',
      },
      {
        'name': 'Michael Johnson',
        'email': 'michael.johnson@stark.com',
        'type1': 'Full-Time',
        'position': 'UI/UX Designer',
        'type2': 'On-Site',
      },
      {
        'name': 'Robert Wilson',
        'email': 'robert.wilson@stark.com',
        'type1': 'Contract',
        'position': 'DevOps Engineer',
        'type2': 'On-Site',
      },
      {
        'name': 'Emily Davis',
        'email': 'emily.davis@stark.com',
        'type1': 'Full-Time',
        'position': 'Product Manager',
        'type2': 'On-Site',
      },
      {
        'name': 'David Brown',
        'email': 'david.brown@stark.com',
        'type1': 'Part-Time',
        'position': 'Marketing Specialist',
        'type2': 'Remote',
      },
    ];

    for (var w in dummyWorkers) {
      batch.set(workersColl.doc(), {
        ...w,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 2. Seed Attendance (matches workers list)
    final dummyAttendance = [
      {
        'name': 'John Smith',
        'email': 'john.smith@stark.com',
        'role': 'Senior Web Developer',
        'status': 'Present',
        'attendanceType': 'Remote',
        'workType': 'Full Time',
      },
      {
        'name': 'Michael Johnson',
        'email': 'michael.johnson@stark.com',
        'role': 'UI/UX Designer',
        'status': 'Present',
        'attendanceType': 'On-Site',
        'workType': 'Full Time',
      },
      {
        'name': 'Robert Wilson',
        'email': 'robert.wilson@stark.com',
        'role': 'DevOps Engineer',
        'status': 'Absent',
        'attendanceType': 'On-Site',
        'workType': 'Contract',
      },
      {
        'name': 'Emily Davis',
        'email': 'emily.davis@stark.com',
        'role': 'Product Manager',
        'status': 'Present',
        'attendanceType': 'On-Site',
        'workType': 'Full Time',
      },
      {
        'name': 'David Brown',
        'email': 'david.brown@stark.com',
        'role': 'Marketing Specialist',
        'status': 'Leave',
        'attendanceType': 'Remote',
        'workType': 'Part Time',
      },
    ];

    for (var a in dummyAttendance) {
      await attendanceColl.add({
        ...a,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 3. Seed Expenses (matches workers list)
    final dummyExpenses = [
      {
        'name': 'John Smith',
        'date': '05/06/2026',
        'category': 'Client Dinner',
        'amount': 124.50,
      },
      {
        'name': 'Michael Johnson',
        'date': '04/06/2026',
        'category': 'Figma Subscription',
        'amount': 45.00,
      },
      {
        'name': 'Emily Davis',
        'date': '02/06/2026',
        'category': 'Office Keyboard',
        'amount': 89.99,
      },
      {
        'name': 'Robert Wilson',
        'date': '01/06/2026',
        'category': 'AWS Cloud Hosting',
        'amount': 250.00,
      },
      {
        'name': 'David Brown',
        'date': '28/05/2026',
        'category': 'Google Ads Campaign',
        'amount': 500.00,
      },
    ];

    for (var e in dummyExpenses) {
      await expensesColl.add({...e, 'createdAt': FieldValue.serverTimestamp()});
    }

    // 4. Seed Payroll (matches workers list)
    final dummyPayroll = [
      {
        'name': 'John Smith',
        'email': 'john.smith@stark.com',
        'position': 'Senior Web Developer',
        'contact': '+1 555-0101',
        'status': 'Active',
        'totalWorkDays': '240',
        'absents': '04',
        'leaves': '08',
        'overtimeDays': '12',
        'salary': '\$ 95,000',
      },
      {
        'name': 'Michael Johnson',
        'email': 'michael.johnson@stark.com',
        'position': 'UI/UX Designer',
        'contact': '+1 555-0102',
        'status': 'Active',
        'totalWorkDays': '230',
        'absents': '02',
        'leaves': '06',
        'overtimeDays': '05',
        'salary': '\$ 75,000',
      },
      {
        'name': 'Robert Wilson',
        'email': 'robert.wilson@stark.com',
        'position': 'DevOps Engineer',
        'contact': '+1 555-0103',
        'status': 'Active',
        'totalWorkDays': '120',
        'absents': '01',
        'leaves': '02',
        'overtimeDays': '00',
        'salary': '\$ 85,000',
      },
      {
        'name': 'Emily Davis',
        'email': 'emily.davis@stark.com',
        'position': 'Product Manager',
        'contact': '+1 555-0104',
        'status': 'Active',
        'totalWorkDays': '250',
        'absents': '01',
        'leaves': '10',
        'overtimeDays': '15',
        'salary': '\$ 110,000',
      },
      {
        'name': 'David Brown',
        'email': 'david.brown@stark.com',
        'position': 'Marketing Specialist',
        'contact': '+1 555-0105',
        'status': 'Active',
        'totalWorkDays': '180',
        'absents': '05',
        'leaves': '12',
        'overtimeDays': '02',
        'salary': '\$ 60,000',
      },
    ];

    for (var p in dummyPayroll) {
      await payrollColl.add({...p, 'createdAt': FieldValue.serverTimestamp()});
    }

    // 5. Seed Time Off requests (matches workers list)
    final dummyTimeoff = [
      {
        'name': 'John Smith',
        'email': 'john.smith@stark.com',
        'position': 'Senior Web Developer',
        'contact': '+1 555-0101',
        'action': 'Annual Leave',
      },
      {
        'name': 'Michael Johnson',
        'email': 'michael.johnson@stark.com',
        'position': 'UI/UX Designer',
        'contact': '+1 555-0102',
        'action': 'Sick Leave',
      },
      {
        'name': 'Robert Wilson',
        'email': 'robert.wilson@stark.com',
        'position': 'DevOps Engineer',
        'contact': '+1 555-0103',
        'action': 'Casual Leave',
      },
      {
        'name': 'David Brown',
        'email': 'david.brown@stark.com',
        'position': 'Marketing Specialist',
        'contact': '+1 555-0105',
        'action': 'Maternity Leave',
      },
    ];

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
