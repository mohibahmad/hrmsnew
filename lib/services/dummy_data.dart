import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DummyData {

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      try {
        final workersJson = prefs.getString('dummy_workers');
        if (workersJson != null && workersJson.isNotEmpty) {
          final list = (jsonDecode(workersJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            workers
              ..clear()
              ..addAll(list);
          }
        }
      } catch (e) {
       }

      try {
        final expensesJson = prefs.getString('dummy_expenses');
        if (expensesJson != null && expensesJson.isNotEmpty) {
          final list = (jsonDecode(expensesJson) as List)
              .cast<Map<String, dynamic>>();
          final hasOldWorkerNames = list.any((e) {
            final name = (e['name'] ?? '').toString();
            return name == 'Michael Johnson' ||
                name == 'Emily Davis' ||
                name == 'Robert Wilson' ||
                name == 'David Brown' ||
                name == 'James Miller' ||
                name == 'Sophia Martinez' ||
                name == 'Daniel Anderson' ||
                name == 'Olivia Thomas' ||
                name == 'Lucas Taylor' ||
                name == 'Amelia White' ||
                name == 'John Smith' ||
                name == 'Benjamin Harris' ||
                name == 'Charlotte Martin' ||
                name == 'Henry Thompson' ||
                name == 'Sarah Connor' ||
                name == 'Mike Peters' ||
                name == 'Laura Palmer' ||
                name == 'Tom Hardy' ||
                name == 'Nina Dobrev' ||
                name == 'Ryan Gosling' ||
                name == 'Emma Watson' ||
                name == 'Chris Evans' ||
                name == 'Scarlett Johansson' ||
                name == 'Robert Downey';
          });
          if (list.isNotEmpty && !hasOldWorkerNames) {
            expenses
              ..clear()
              ..addAll(list);
          }
        }
      } catch (e) {
        // ignore
      }

      try {
        final attendanceJson = prefs.getString('dummy_attendance');
        if (attendanceJson != null && attendanceJson.isNotEmpty) {
          final list = (jsonDecode(attendanceJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            attendance
              ..clear()
              ..addAll(list);
          }
        }
      } catch (e) {
        // ignore
      }

      try {
        final payrollJson = prefs.getString('dummy_payroll');
        if (payrollJson != null && payrollJson.isNotEmpty) {
          final list = (jsonDecode(payrollJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            payroll
              ..clear()
              ..addAll(list);
          }
        }
      } catch (e) {
        // ignore
      }

      try {
        final timeoffJson = prefs.getString('dummy_timeoff');
        if (timeoffJson != null && timeoffJson.isNotEmpty) {
          final list = (jsonDecode(timeoffJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            timeoff
              ..clear()
              ..addAll(list);
          }
        }
      } catch (e) {
        // ignore
      }

      try {
        final assetsJson = prefs.getString('dummy_assets');
        if (assetsJson != null && assetsJson.isNotEmpty) {
          final list = (jsonDecode(assetsJson) as List)
              .cast<Map<String, dynamic>>();
          if (list.isNotEmpty) {
            assets
              ..clear()
              ..addAll(list);
          }
        }
      } catch (e) {
        // ignore
      }

      // Populate defaults for leave fields in case they are missing
      for (var w in workers) {
        if (w['annualLeaves'] == null || w['annualLeaves'].toString().trim().isEmpty) {
          w['annualLeaves'] = '12';
        }
        if (w['sickLeaves'] == null || w['sickLeaves'].toString().trim().isEmpty) {
          w['sickLeaves'] = '8';
        }
        if (w['casualLeaves'] == null || w['casualLeaves'].toString().trim().isEmpty) {
          w['casualLeaves'] = '10';
        }
        if (w['leavesUsed'] == null || w['leavesUsed'].toString().trim().isEmpty) {
          w['leavesUsed'] = '0';
        }
      }
    } catch (e) {
      // ignore
    }
  }

  static Future<void> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dummy_workers', jsonEncode(workers));
      await prefs.setString('dummy_expenses', jsonEncode(expenses));
      await prefs.setString('dummy_attendance', jsonEncode(attendance));
      await prefs.setString('dummy_payroll', jsonEncode(payroll));
      await prefs.setString('dummy_timeoff', jsonEncode(timeoff));
      await prefs.setString('dummy_assets', jsonEncode(assets));
    } catch (_) {
      // Ignore save errors
    }
  }

  static final List<Map<String, dynamic>> workers = [
    {
      'id': 'dummy_1',
      'name': 'John Smith',
      'email': 'john.smith@stark.com',
      'phone': '+1 555-0101',
      'gender': 'Male',
      'fatherName': 'William Smith',
      'joiningDate': 'January 15, 2022',
      'salaryAmount': '95,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'Senior Web Developer',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_2',
      'name': 'Michael Johnson',
      'email': 'michael.johnson@stark.com',
      'phone': '+1 555-0102',
      'gender': 'Male',
      'fatherName': 'Robert Johnson',
      'joiningDate': 'March 10, 2022',
      'salaryAmount': '75,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'UI/UX Designer',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_3',
      'name': 'Robert Wilson',
      'email': 'robert.wilson@stark.com',
      'phone': '+1 555-0103',
      'gender': 'Male',
      'fatherName': 'James Wilson',
      'joiningDate': 'June 20, 2023',
      'salaryAmount': '85,000',
      'currency': 'USD',
      'type1': 'Contract',
      'position': 'DevOps Engineer',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_4',
      'name': 'Emily Davis',
      'email': 'emily.davis@stark.com',
      'phone': '+1 555-0104',
      'gender': 'Female',
      'fatherName': 'Richard Davis',
      'joiningDate': 'February 5, 2021',
      'salaryAmount': '110,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'Product Manager',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_5',
      'name': 'David Brown',
      'email': 'david.brown@stark.com',
      'phone': '+1 555-0105',
      'gender': 'Male',
      'fatherName': 'Thomas Brown',
      'joiningDate': 'August 12, 2022',
      'salaryAmount': '65,000',
      'currency': 'USD',
      'type1': 'Part-Time',
      'position': 'Marketing Specialist',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_6',
      'name': 'James Miller',
      'email': 'james.miller@stark.com',
      'phone': '+1 555-0106',
      'gender': 'Male',
      'fatherName': 'Charles Miller',
      'joiningDate': 'November 3, 2022',
      'salaryAmount': '90,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'Backend Engineer',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_7',
      'name': 'Sophia Martinez',
      'email': 'sophia.martinez@stark.com',
      'phone': '+1 555-0107',
      'gender': 'Female',
      'fatherName': 'Carlos Martinez',
      'joiningDate': 'April 18, 2021',
      'salaryAmount': '80,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'HR Manager',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_8',
      'name': 'Daniel Anderson',
      'email': 'daniel.anderson@stark.com',
      'phone': '+1 555-0108',
      'gender': 'Male',
      'fatherName': 'Mark Anderson',
      'joiningDate': 'September 25, 2023',
      'salaryAmount': '70,000',
      'currency': 'USD',
      'type1': 'Contract',
      'position': 'Frontend Developer',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_9',
      'name': 'Olivia Thomas',
      'email': 'olivia.thomas@stark.com',
      'phone': '+1 555-0109',
      'gender': 'Female',
      'fatherName': 'Steven Thomas',
      'joiningDate': 'July 8, 2022',
      'salaryAmount': '60,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'QA Engineer',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_10',
      'name': 'Lucas Taylor',
      'email': 'lucas.taylor@stark.com',
      'phone': '+1 555-0110',
      'gender': 'Male',
      'fatherName': 'Paul Taylor',
      'joiningDate': 'May 14, 2021',
      'salaryAmount': '105,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'Solutions Architect',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_11',
      'name': 'Amelia White',
      'email': 'amelia.white@stark.com',
      'phone': '+1 555-0111',
      'gender': 'Female',
      'fatherName': 'George White',
      'joiningDate': 'October 22, 2023',
      'salaryAmount': '55,000',
      'currency': 'USD',
      'type1': 'Part-Time',
      'position': 'Graphic Designer',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_12',
      'name': 'Benjamin Harris',
      'email': 'benjamin.harris@stark.com',
      'phone': '+1 555-0112',
      'gender': 'Male',
      'fatherName': 'Edward Harris',
      'joiningDate': 'December 1, 2022',
      'salaryAmount': '88,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'Mobile Developer',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_13',
      'name': 'Charlotte Martin',
      'email': 'charlotte.martin@stark.com',
      'phone': '+1 555-0113',
      'gender': 'Female',
      'fatherName': 'Henry Martin',
      'joiningDate': 'March 30, 2023',
      'salaryAmount': '92,000',
      'currency': 'USD',
      'type1': 'Full-Time',
      'position': 'Cyber Security Analyst',
      'type2': 'On-Site',
    },
    {
      'id': 'dummy_14',
      'name': 'Henry Thompson',
      'email': 'henry.thompson@stark.com',
      'phone': '+1 555-0114',
      'gender': 'Male',
      'fatherName': 'Frank Thompson',
      'joiningDate': 'January 5, 2024',
      'salaryAmount': '98,000',
      'currency': 'USD',
      'type1': 'Contract',
      'position': 'Data Scientist',
      'type2': 'Remote',
    },
    {
      'id': 'dummy_15',
      'name': 'Harper Garcia',
      'email': 'harper.garcia@stark.com',
      'phone': '+1 555-0115',
      'gender': 'Female',
      'fatherName': 'Miguel Garcia',
      'joiningDate': 'July 19, 2023',
      'salaryAmount': '58,000',
      'currency': 'USD',
      'type1': 'Part-Time',
      'position': 'Technical Writer',
      'type2': 'Remote',
    },
  ];

  static final List<Map<String, dynamic>> expenses = [
    {
      'id': 'dummy_e1',
      'name': 'Client Dinner with Acme Corp',
      'date': '05/06/2026',
      'category': 'Meals',
      'amount': 124.50,
    },
    {
      'id': 'dummy_e2',
      'name': 'Figma Team Subscription',
      'date': '04/06/2026',
      'category': 'Software',
      'amount': 45.00,
    },
    {
      'id': 'dummy_e3',
      'name': 'Wireless Mechanical Keyboard',
      'date': '02/06/2026',
      'category': 'Equipment',
      'amount': 89.99,
    },
    {
      'id': 'dummy_e4',
      'name': 'AWS Cloud Hosting - June',
      'date': '01/06/2026',
      'category': 'Infrastructure',
      'amount': 250.00,
    },
    {
      'id': 'dummy_e5',
      'name': 'Google Ads - Product Launch',
      'date': '28/05/2026',
      'category': 'Marketing',
      'amount': 500.00,
    },
    {
      'id': 'dummy_e6',
      'name': 'GitHub Enterprise License',
      'date': '25/05/2026',
      'category': 'Software',
      'amount': 150.00,
    },
    {
      'id': 'dummy_e7',
      'name': 'Recruiting Software - Quarterly',
      'date': '22/05/2026',
      'category': 'Software',
      'amount': 320.00,
    },
    {
      'id': 'dummy_e8',
      'name': 'Remote Work Internet Allowance',
      'date': '19/05/2026',
      'category': 'Utilities',
      'amount': 60.00,
    },
    {
      'id': 'dummy_e9',
      'name': 'QA Testing Device - Pixel Tablet',
      'date': '15/05/2026',
      'category': 'Equipment',
      'amount': 299.00,
    },
    {
      'id': 'dummy_e10',
      'name': 'Ergonomic Office Chair',
      'date': '10/05/2026',
      'category': 'Furniture',
      'amount': 180.00,
    },
    {
      'id': 'dummy_e11',
      'name': 'Adobe Creative Cloud - Annual',
      'date': '08/05/2026',
      'category': 'Software',
      'amount': 79.99,
    },
    {
      'id': 'dummy_e12',
      'name': 'Tech Conference 2026 Tickets',
      'date': '05/05/2026',
      'category': 'Events',
      'amount': 400.00,
    },
    {
      'id': 'dummy_e13',
      'name': 'Apple Developer Program Renewal',
      'date': '06/06/2026',
      'category': 'Software',
      'amount': 99.00,
    },
    {
      'id': 'dummy_e14',
      'name': 'YubiKey Security Keys - Team',
      'date': '05/06/2026',
      'category': 'Security',
      'amount': 55.00,
    },
    {
      'id': 'dummy_e15',
      'name': 'DataCamp Team Subscription',
      'date': '03/06/2026',
      'category': 'Training',
      'amount': 150.00,
    },
    {
      'id': 'dummy_e16',
      'name': 'Team Lunch - Q2 Review',
      'date': '07/06/2026',
      'category': 'Meals',
      'amount': 210.00,
    },
    {
      'id': 'dummy_e17',
      'name': 'JetBrains All Products Pack',
      'date': '08/06/2026',
      'category': 'Software',
      'amount': 350.00,
    },
    {
      'id': 'dummy_e18',
      'name': 'Client Visit - Flight & Hotel',
      'date': '09/06/2026',
      'category': 'Travel',
      'amount': 475.00,
    },
    {
      'id': 'dummy_e19',
      'name': 'Office Supplies - Printer Ink',
      'date': '10/06/2026',
      'category': 'Supplies',
      'amount': 65.00,
    },
    {
      'id': 'dummy_e20',
      'name': 'Client Meeting - Downtown',
      'date': '11/06/2026',
      'category': 'Travel',
      'amount': 180.00,
    },
    {
      'id': 'dummy_e21',
      'name': 'Hotel Booking - Partner Summit',
      'date': '12/06/2026',
      'category': 'Travel',
      'amount': 520.00,
    },
    {
      'id': 'dummy_e22',
      'name': 'Office Internet Bill - June',
      'date': '13/06/2026',
      'category': 'Utilities',
      'amount': 45.00,
    },
    {
      'id': 'dummy_e23',
      'name': 'Client Dinner - Product Demo',
      'date': '14/06/2026',
      'category': 'Meals',
      'amount': 290.00,
    },
    {
      'id': 'dummy_e24',
      'name': 'Social Media Marketing Campaign',
      'date': '15/06/2026',
      'category': 'Marketing',
      'amount': 750.00,
    },
    {
      'id': 'dummy_e25',
      'name': 'Flight Tickets - Tech Conference',
      'date': '16/06/2026',
      'category': 'Travel',
      'amount': 890.00,
    },
  ];

  static final List<Map<String, dynamic>> attendance = [
    {
      'id': 'dummy_a1',
      'name': 'John Smith',
      'email': 'john.smith@stark.com',
      'role': 'Senior Web Developer',
      'status': 'Present',
      'attendanceType': 'Remote',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a2',
      'name': 'Michael Johnson',
      'email': 'michael.johnson@stark.com',
      'role': 'UI/UX Designer',
      'status': 'Present',
      'attendanceType': 'On-Site',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a3',
      'name': 'Robert Wilson',
      'email': 'robert.wilson@stark.com',
      'role': 'DevOps Engineer',
      'status': 'Absent',
      'attendanceType': 'On-Site',
      'workType': 'Contract',
    },
    {
      'id': 'dummy_a4',
      'name': 'Emily Davis',
      'email': 'emily.davis@stark.com',
      'role': 'Product Manager',
      'status': 'Present',
      'attendanceType': 'On-Site',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a5',
      'name': 'David Brown',
      'email': 'david.brown@stark.com',
      'role': 'Marketing Specialist',
      'status': 'Leave',
      'attendanceType': 'Remote',
      'workType': 'Part Time',
    },
    {
      'id': 'dummy_a6',
      'name': 'James Miller',
      'email': 'james.miller@stark.com',
      'role': 'Backend Engineer',
      'status': 'Present',
      'attendanceType': 'Remote',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a7',
      'name': 'Sophia Martinez',
      'email': 'sophia.martinez@stark.com',
      'role': 'HR Manager',
      'status': 'Present',
      'attendanceType': 'On-Site',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a8',
      'name': 'Daniel Anderson',
      'email': 'daniel.anderson@stark.com',
      'role': 'Frontend Developer',
      'status': 'Present',
      'attendanceType': 'Remote',
      'workType': 'Contract',
    },
    {
      'id': 'dummy_a9',
      'name': 'Olivia Thomas',
      'email': 'olivia.thomas@stark.com',
      'role': 'QA Engineer',
      'status': 'Present',
      'attendanceType': 'On-Site',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a10',
      'name': 'Lucas Taylor',
      'email': 'lucas.taylor@stark.com',
      'role': 'Solutions Architect',
      'status': 'Absent',
      'attendanceType': 'On-Site',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a11',
      'name': 'Amelia White',
      'email': 'amelia.white@stark.com',
      'role': 'Graphic Designer',
      'status': 'Leave',
      'attendanceType': 'Remote',
      'workType': 'Part Time',
      'type': 'Sick Leave',
      'desc': 'Sick leave due to fever, doctor advised rest for 2 days.',
    },
    {
      'id': 'dummy_a12',
      'name': 'Benjamin Harris',
      'email': 'benjamin.harris@stark.com',
      'role': 'Mobile Developer',
      'status': 'Present',
      'attendanceType': 'Remote',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a13',
      'name': 'Charlotte Martin',
      'email': 'charlotte.martin@stark.com',
      'role': 'Cyber Security Analyst',
      'status': 'Present',
      'attendanceType': 'On-Site',
      'workType': 'Full Time',
    },
    {
      'id': 'dummy_a14',
      'name': 'Henry Thompson',
      'email': 'henry.thompson@stark.com',
      'role': 'Data Scientist',
      'status': 'Absent',
      'attendanceType': 'Remote',
      'workType': 'Contract',
    },
    {
      'id': 'dummy_a15',
      'name': 'Harper Garcia',
      'email': 'harper.garcia@stark.com',
      'role': 'Technical Writer',
      'status': 'Leave',
      'attendanceType': 'Remote',
      'workType': 'Part Time',
    },
  ];

  static final List<Map<String, dynamic>> payroll = [
    {
      'id': 'dummy_p1',
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
      'id': 'dummy_p2',
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
      'id': 'dummy_p3',
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
      'id': 'dummy_p4',
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
      'id': 'dummy_p5',
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
    {
      'id': 'dummy_p6',
      'name': 'James Miller',
      'email': 'james.miller@stark.com',
      'position': 'Backend Engineer',
      'contact': '+1 555-0106',
      'status': 'Active',
      'totalWorkDays': '220',
      'absents': '03',
      'leaves': '05',
      'overtimeDays': '08',
      'salary': '\$ 80,000',
    },
    {
      'id': 'dummy_p7',
      'name': 'Sophia Martinez',
      'email': 'sophia.martinez@stark.com',
      'position': 'HR Manager',
      'contact': '+1 555-0107',
      'status': 'Active',
      'totalWorkDays': '240',
      'absents': '00',
      'leaves': '04',
      'overtimeDays': '02',
      'salary': '\$ 70,000',
    },
    {
      'id': 'dummy_p8',
      'name': 'Daniel Anderson',
      'email': 'daniel.anderson@stark.com',
      'position': 'Frontend Developer',
      'contact': '+1 555-0108',
      'status': 'Active',
      'totalWorkDays': '150',
      'absents': '02',
      'leaves': '03',
      'overtimeDays': '04',
      'salary': '\$ 65,000',
    },
    {
      'id': 'dummy_p9',
      'name': 'Olivia Thomas',
      'email': 'olivia.thomas@stark.com',
      'position': 'QA Engineer',
      'contact': '+1 555-0109',
      'status': 'Active',
      'totalWorkDays': '245',
      'absents': '01',
      'leaves': '05',
      'overtimeDays': '06',
      'salary': '\$ 68,000',
    },
    {
      'id': 'dummy_p10',
      'name': 'Lucas Taylor',
      'email': 'lucas.taylor@stark.com',
      'position': 'Solutions Architect',
      'contact': '+1 555-0110',
      'status': 'Active',
      'totalWorkDays': '210',
      'absents': '04',
      'leaves': '08',
      'overtimeDays': '10',
      'salary': '\$ 120,000',
    },
    {
      'id': 'dummy_p11',
      'name': 'Amelia White',
      'email': 'amelia.white@stark.com',
      'position': 'Graphic Designer',
      'contact': '+1 555-0111',
      'status': 'Active',
      'totalWorkDays': '160',
      'absents': '03',
      'leaves': '15',
      'overtimeDays': '01',
      'salary': '\$ 55,000',
    },
    {
      'id': 'dummy_p12',
      'name': 'Benjamin Harris',
      'email': 'benjamin.harris@stark.com',
      'position': 'Mobile Developer',
      'contact': '+1 555-0112',
      'status': 'Active',
      'totalWorkDays': '220',
      'absents': '02',
      'leaves': '05',
      'overtimeDays': '10',
      'salary': '\$ 88,000',
    },
    {
      'id': 'dummy_p13',
      'name': 'Charlotte Martin',
      'email': 'charlotte.martin@stark.com',
      'position': 'Cyber Security Analyst',
      'contact': '+1 555-0113',
      'status': 'Active',
      'totalWorkDays': '240',
      'absents': '01',
      'leaves': '04',
      'overtimeDays': '02',
      'salary': '\$ 90,000',
    },
    {
      'id': 'dummy_p14',
      'name': 'Henry Thompson',
      'email': 'henry.thompson@stark.com',
      'position': 'Data Scientist',
      'contact': '+1 555-0114',
      'status': 'Active',
      'totalWorkDays': '125',
      'absents': '01',
      'leaves': '03',
      'overtimeDays': '00',
      'salary': '\$ 95,000',
    },
    {
      'id': 'dummy_p15',
      'name': 'Harper Garcia',
      'email': 'harper.garcia@stark.com',
      'position': 'Technical Writer',
      'contact': '+1 555-0115',
      'status': 'Active',
      'totalWorkDays': '150',
      'absents': '03',
      'leaves': '12',
      'overtimeDays': '01',
      'salary': '\$ 48,000',
    },
  ];

  static final List<Map<String, dynamic>> timeoff = [
    {
      'id': 'dummy_t1',
      'name': 'John Smith',
      'email': 'john.smith@stark.com',
      'position': 'Senior Web Developer',
      'contact': '+1 555-0101',
      'action': 'Annual Leave',
      'startDate': '2026-07-10',
      'endDate': '2026-07-15',
      'requestedDays': 5,
    },
    {
      'id': 'dummy_t2',
      'name': 'Michael Johnson',
      'email': 'michael.johnson@stark.com',
      'position': 'UI/UX Designer',
      'contact': '+1 555-0102',
      'action': 'Sick Leave',
      'startDate': '2026-07-12',
      'endDate': '2026-07-13',
      'requestedDays': 2,
    },
    {
      'id': 'dummy_t3',
      'name': 'Robert Wilson',
      'email': 'robert.wilson@stark.com',
      'position': 'DevOps Engineer',
      'contact': '+1 555-0103',
      'action': 'Casual Leave',
      'startDate': '2026-07-08',
      'endDate': '2026-07-09',
      'requestedDays': 2,
    },
    {
      'id': 'dummy_t4',
      'name': 'David Brown',
      'email': 'david.brown@stark.com',
      'position': 'Marketing Specialist',
      'contact': '+1 555-0105',
      'action': 'Maternity Leave',
      'startDate': '2026-06-20',
      'endDate': '2026-07-20',
      'requestedDays': 30,
    },
    {
      'id': 'dummy_t5',
      'name': 'James Miller',
      'email': 'james.miller@stark.com',
      'position': 'Backend Engineer',
      'contact': '+1 555-0106',
      'action': 'Annual Leave',
      'startDate': '2026-07-11',
      'endDate': '2026-07-14',
      'requestedDays': 3,
    },
    {
      'id': 'dummy_t6',
      'name': 'Sophia Martinez',
      'email': 'sophia.martinez@stark.com',
      'position': 'HR Manager',
      'contact': '+1 555-0107',
      'action': 'Sick Leave',
      'startDate': '2026-07-13',
      'endDate': '2026-07-13',
      'requestedDays': 1,
    },
    {
      'id': 'dummy_t7',
      'name': 'Daniel Anderson',
      'email': 'daniel.anderson@stark.com',
      'position': 'Frontend Developer',
      'contact': '+1 555-0108',
      'action': 'Casual Leave',
      'startDate': '2026-07-07',
      'endDate': '2026-07-08',
      'requestedDays': 2,
    },
    {
      'id': 'dummy_t8',
      'name': 'Olivia Thomas',
      'email': 'olivia.thomas@stark.com',
      'position': 'QA Engineer',
      'contact': '+1 555-0109',
      'action': 'Maternity Leave',
      'startDate': '2026-06-01',
      'endDate': '2026-07-01',
      'requestedDays': 30,
    },
    {
      'id': 'dummy_t9',
      'name': 'Lucas Taylor',
      'email': 'lucas.taylor@stark.com',
      'position': 'Solutions Architect',
      'contact': '+1 555-0110',
      'action': 'Annual Leave',
      'startDate': '2026-07-09',
      'endDate': '2026-07-12',
      'requestedDays': 3,
    },
    {
      'id': 'dummy_t10',
      'name': 'Amelia White',
      'email': 'amelia.white@stark.com',
      'position': 'Graphic Designer',
      'contact': '+1 555-0111',
      'action': 'Sick Leave',
      'startDate': '2026-07-06',
      'endDate': '2026-07-07',
      'requestedDays': 2,
    },
    {
      'id': 'dummy_t11',
      'name': 'Benjamin Harris',
      'email': 'benjamin.harris@stark.com',
      'position': 'Mobile Developer',
      'contact': '+1 555-0112',
      'action': 'Annual Leave',
      'startDate': '2026-07-01',
      'endDate': '2026-07-05',
      'requestedDays': 5,
    },
    {
      'id': 'dummy_t12',
      'name': 'Charlotte Martin',
      'email': 'charlotte.martin@stark.com',
      'position': 'Cyber Security Analyst',
      'contact': '+1 555-0113',
      'action': 'Sick Leave',
      'startDate': '2026-07-10',
      'endDate': '2026-07-11',
      'requestedDays': 2,
    },
  ];

  static final Map<String, List<Map<String, dynamic>>> holidays = {
    'May': [
      {
        'day': 1,
        'month': 'May',
        'remainingDays': '05',
        'dayOfWeek': 'Saturday',
        'name': 'Labour Day',
        'isEnabled': true,
      },
      {
        'day': 3,
        'month': 'May',
        'remainingDays': '07',
        'dayOfWeek': 'Monday',
        'name': 'Eid-ul-Fitr Holiday',
        'isEnabled': true,
      },
      {
        'day': 6,
        'month': 'May',
        'remainingDays': '10',
        'dayOfWeek': 'Thursday',
        'name': 'Memorial Day',
        'isEnabled': true,
      },
      {
        'day': 10,
        'month': 'May',
        'remainingDays': '14',
        'dayOfWeek': 'Monday',
        'name': 'Eid-ul-Adha Holiday',
        'isEnabled': true,
      },
      {
        'day': 14,
        'month': 'May',
        'remainingDays': '18',
        'dayOfWeek': 'Sunday',
        'name': 'Mother\'s Day',
        'isEnabled': true,
      },
      {
        'day': 15,
        'month': 'May',
        'remainingDays': '19',
        'dayOfWeek': 'Monday',
        'name': 'Independence Day',
        'isEnabled': true,
      },
      {
        'day': 18,
        'month': 'May',
        'remainingDays': '22',
        'dayOfWeek': 'Thursday',
        'name': 'Founder\'s Day',
        'isEnabled': true,
      },
      {
        'day': 20,
        'month': 'May',
        'remainingDays': '24',
        'dayOfWeek': 'Saturday',
        'name': 'Spring Break',
        'isEnabled': true,
      },
      {
        'day': 22,
        'month': 'May',
        'remainingDays': '26',
        'dayOfWeek': 'Monday',
        'name': 'Youth Day',
        'isEnabled': true,
      },
      {
        'day': 25,
        'month': 'May',
        'remainingDays': '29',
        'dayOfWeek': 'Thursday',
        'name': 'National Day',
        'isEnabled': true,
      },
      {
        'day': 26,
        'month': 'May',
        'remainingDays': '30',
        'dayOfWeek': 'Friday',
        'name': 'Victoria Day',
        'isEnabled': true,
      },
      {
        'day': 28,
        'month': 'May',
        'remainingDays': '32',
        'dayOfWeek': 'Sunday',
        'name': 'Bank Holiday',
        'isEnabled': true,
      },
      {
        'day': 29,
        'month': 'May',
        'remainingDays': '33',
        'dayOfWeek': 'Monday',
        'name': 'Ascension Day',
        'isEnabled': true,
      },
      {
        'day': 30,
        'month': 'May',
        'remainingDays': '34',
        'dayOfWeek': 'Tuesday',
        'name': 'Unity Day',
        'isEnabled': true,
      },
      {
        'day': 31,
        'month': 'May',
        'remainingDays': '35',
        'dayOfWeek': 'Wednesday',
        'name': 'Memorial Feast',
        'isEnabled': true,
      },
    ],
    'Feb': [
      {
        'day': 1,
        'month': 'Feb',
        'remainingDays': '02',
        'dayOfWeek': 'Wednesday',
        'name': 'Groundhog Day',
        'isEnabled': true,
      },
      {
        'day': 6,
        'month': 'Feb',
        'remainingDays': '07',
        'dayOfWeek': 'Monday',
        'name': 'Super Bowl',
        'isEnabled': true,
      },
      {
        'day': 14,
        'month': 'Feb',
        'remainingDays': '15',
        'dayOfWeek': 'Tuesday',
        'name': 'Valentine\'s Day',
        'isEnabled': true,
      },
      {
        'day': 26,
        'month': 'Feb',
        'remainingDays': '27',
        'dayOfWeek': 'Monday',
        'name': 'Presidents\' Day',
        'isEnabled': true,
      },
    ],
    'Jun': [
      {
        'day': 5,
        'month': 'Jun',
        'remainingDays': '05',
        'dayOfWeek': 'Thursday',
        'name': 'Eid-ul-Adha',
        'isEnabled': true,
      },
      {
        'day': 14,
        'month': 'Jun',
        'remainingDays': '14',
        'dayOfWeek': 'Saturday',
        'name': 'Flag Day',
        'isEnabled': true,
      },
      {
        'day': 19,
        'month': 'Jun',
        'remainingDays': '19',
        'dayOfWeek': 'Thursday',
        'name': 'Juneteenth',
        'isEnabled': true,
      },
      {
        'day': 21,
        'month': 'Jun',
        'remainingDays': '21',
        'dayOfWeek': 'Saturday',
        'name': 'Summer Solstice',
        'isEnabled': true,
      },
      {
        'day': 30,
        'month': 'Jun',
        'remainingDays': '30',
        'dayOfWeek': 'Monday',
        'name': 'Mid-Year Break',
        'isEnabled': true,
      },
    ],
    'Jul': [
      {
        'day': 4,
        'month': 'Jul',
        'remainingDays': '04',
        'dayOfWeek': 'Friday',
        'name': 'Independence Day',
        'isEnabled': true,
      },
      {
        'day': 12,
        'month': 'Jul',
        'remainingDays': '12',
        'dayOfWeek': 'Saturday',
        'name': 'Summer Festival',
        'isEnabled': true,
      },
      {
        'day': 20,
        'month': 'Jul',
        'remainingDays': '20',
        'dayOfWeek': 'Sunday',
        'name': 'National Ice Cream Day',
        'isEnabled': true,
      },
      {
        'day': 28,
        'month': 'Jul',
        'remainingDays': '28',
        'dayOfWeek': 'Monday',
        'name': 'Company Retreat',
        'isEnabled': true,
      },
    ],
  };

  static final List<Map<String, dynamic>> assets = [
    {
      'name': 'Emily Davis',
      'position': 'Product Manager',
      'type': 'Laptop',
      'dateLoaned': '15/01/2025',
      'dateReturned': '15/01/2025',
      'isReturned': true,
    },
    {
      'name': 'Amelia White',
      'position': 'Graphic Designer',
      'type': 'Mouse',
      'dateLoaned': '10/03/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'Charlotte Martin',
      'position': 'Cyber Security Analyst',
      'type': 'Keyboard',
      'dateLoaned': '20/05/2025',
      'dateReturned': '20/05/2025',
      'isReturned': true,
    },
    {
      'name': 'Sophia Martinez',
      'position': 'HR Manager',
      'type': 'Mac',
      'dateLoaned': '05/02/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'Daniel Anderson',
      'position': 'Frontend Developer',
      'type': 'Table',
      'dateLoaned': '12/04/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'John Smith',
      'position': 'Backend Developer',
      'type': 'Monitor',
      'dateLoaned': '18/06/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'Michael Johnson',
      'position': 'DevOps Engineer',
      'type': 'Headphone',
      'dateLoaned': '22/06/2025',
      'dateReturned': '22/06/2025',
      'isReturned': true,
    },
    {
      'name': 'Olivia Thomas',
      'position': 'UI Designer',
      'type': 'iPad',
      'dateLoaned': '01/07/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'James Miller',
      'position': 'Backend Engineer',
      'type': 'Laptop',
      'dateLoaned': '05/07/2025',
      'dateReturned': '05/07/2025',
      'isReturned': true,
    },
    {
      'name': 'Harper Garcia',
      'position': 'Technical Writer',
      'type': 'Keyboard',
      'dateLoaned': '10/08/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'Benjamin Harris',
      'position': 'Mobile Developer',
      'type': 'iPhone',
      'dateLoaned': '15/08/2025',
      'dateReturned': 'in_use',
      'isReturned': false,
    },
    {
      'name': 'Lucas Taylor',
      'position': 'Solutions Architect',
      'type': 'Monitor',
      'dateLoaned': '20/09/2025',
      'dateReturned': '20/09/2025',
      'isReturned': true,
    },
  ];
}
