import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import 'workers.dart';
import 'attendance_screen.dart';
import 'workers_attendance_screen.dart';
import 'payroll_screen.dart';
import 'time_off.dart';
import 'assign_time_off.dart';
import 'assets_screen.dart';
import 'holidays_screen.dart';
import 'expenses_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../utils/logout_dialog.dart';
import '../widgets/notification_sidebar.dart';
import 'login_screen.dart';
import '../services/payroll_service.dart';
import '../services/dummy_data.dart';
import '../utils/date_utils.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import '../widgets/sidebar_widget.dart';
import '../widgets/dashboard/top_header.dart';
import '../widgets/dashboard/total_workers_card.dart';
import '../widgets/dashboard/sparkline_card.dart';
import '../widgets/dashboard/attendance_line_chart.dart';
import '../widgets/dashboard/leave_types_pie_chart.dart';
import '../widgets/dashboard/holiday_card.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;
  final int initialSubIndex;

  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.initialSubIndex = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  late int _selectedSubIndex;
  String _selectedPeriod = 'Yearly';
  bool _showProfile = false;
  bool _showAssignTimeOff = false;
  bool _showNotifications = false;
  bool _showWorkersAttendance = false;
  final List<bool> _activatedScreens = List.filled(12, false);

  Widget _getScreen(int index) {
    switch (index) {
      case 1:
        return WorkersScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 2:
        return AttendanceScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          onWorkersAttendanceTap: () {
            setState(() {
              _showWorkersAttendance = true;
            });
          },
        );
      case 3:
        return PayrollScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onAssignTimeOff: () {
            setState(() {
              _selectedTimeOffWorker = null;
              _showAssignTimeOff = true;
            });
          },
          onNotificationTap: _toggleNotifications,
        );
      case 4:
        return TimeOffScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onAssignTimeOff: (worker) {
            setState(() {
              _selectedTimeOffWorker = worker;
              _showAssignTimeOff = true;
            });
          },
          onNotificationTap: _toggleNotifications,
        );
      case 5:
        return AssetsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 6:
        return HolidaysScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 7:
        return ExpensesScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
        );
      case 8:
        return SettingsScreen(
          onLogout: _handleLogout,
          onProfileTap: _openProfile,
          isGuest: AuthService().currentUser?.isAnonymous ?? false,
          onNotificationTap: _toggleNotifications,
        );
      case 9:
        return AssignTimeOffScreen(
          onBack: () => setState(() {
            _showAssignTimeOff = false;
            _selectedTimeOffWorker = null;
          }),
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          initialWorker: _selectedTimeOffWorker,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  int _getStackIndex() {
    if (_showWorkersAttendance) return 11;
    if (_showProfile) return 10;
    if (_showAssignTimeOff) return 9;
    if (_selectedIndex == 0) return 0;
    if (_selectedIndex == 1) return 1;
    if (_selectedIndex == 2) {
      if (_selectedSubIndex == 0) return 2;
      if (_selectedSubIndex == 1) return 3;
      if (_selectedSubIndex == 2) return 4;
      if (_selectedSubIndex == 3) return 5;
      if (_selectedSubIndex == 4) return 6;
    }
    if (_selectedIndex == 3) return 7;
    if (_selectedIndex == 4) return 8;
    return 0;
  }

  int _totalWorkersCount = 0;
  int _maleWorkersCount = 0;
  int _femaleWorkersCount = 0;
  double _totalExpensesSum = 0.0;
  double _totalSalarySum = 0.0;
  List<Map<String, dynamic>> _rawExpensesDocs = [];
  List<Map<String, dynamic>> _rawPayrollDocs = [];
  List<Map<String, dynamic>> _holidays = [];
  StreamSubscription? _holidaysSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _expensesSub;
  StreamSubscription? _payrollSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _timeoffSub;
  StreamSubscription? _notifSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  int _totalAttendanceCount = 0;
  int _totalTimeoffCount = 0;
  int _unreadNotifCount = 0;
  List<Map<String, dynamic>> _attendanceDocs = [];
  List<Map<String, dynamic>> _timeoffDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  Map<String, dynamic>? _selectedTimeOffWorker;
  bool _isPremium = false;
  bool _dashboardReady = false;

  @override
  void dispose() {
    _holidaysSub?.cancel();
    _workersSub?.cancel();
    _expensesSub?.cancel();
    _payrollSub?.cancel();
    _attendanceSub?.cancel();
    _timeoffSub?.cancel();
    _notifSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPremiumStatus() async {
    bool isPremium = false;
    final user = AuthService().currentUser;
    // Always read premium status from Firestore, never trust local cache.
    if (user != null && !user.isAnonymous) {
      try {
        final profile = await FirestoreService().getUserProfile();
        isPremium = profile?['isPremium'] == true;
        // Sync to local preferences so other parts of the app (PremiumGate, etc.)
        // also see the correct value without another Firestore call.
        await PreferencesService.setPremium(isPremium);
      } catch (_) {
        // Fallback to local cache if Firestore is unreachable
        isPremium = await PreferencesService.isPremium();
      }
    }
    if (mounted) setState(() => _isPremium = isPremium);
  }

  Future<void> _checkProfileExistsOrLogout() async {
    final user = AuthService().currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      final profile = await FirestoreService().getUserProfile();
      if (profile == null) {
        await AuthService().signOut();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    } catch (_) {
      // Firestore error — don't logout, let the app retry
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _selectedSubIndex = widget.initialSubIndex;
    final stackIdx = _getStackIndex();
    _activatedScreens[stackIdx] = true;
    _activatedScreens[0] = true;
    final currentUser = AuthService().currentUser;
    // Try to restore profile pic from local storage first (survives restarts)
    _restoreProfilePic(currentUser);
    _loadDashboardData();
    // Defer the heavy dashboard (charts/cards) build to after the first frame
    // so the sign-in -> home page transition stays smooth.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _dashboardReady = true);
    });
    // Real-time listener for premium status changes from Firestore
    _startPremiumListener();
    // Load premium status first, then show dialog if needed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkProfileExistsOrLogout();
      await _loadPremiumStatus();
    });
  }

  Future<void> _restoreProfilePic(User? currentUser) async {
    if (currentUser != null && !currentUser.isAnonymous) {
      try {
        final profile = await FirestoreService().getUserProfile();
        if (mounted && profile != null) {
          final pic = profile['profilePic'];
          if (pic != null && pic.toString().isNotEmpty) {
            AuthService.profilePicNotifier.value = pic.toString();
            await PreferencesService.setProfilePicUrl(pic.toString());
            return;
          }
        }
      } catch (_) {}
    }

    final cachedUrl = PreferencesService.cachedProfilePicUrl;
    if (cachedUrl != null &&
        cachedUrl.isNotEmpty &&
        cachedUrl.startsWith('http')) {
      AuthService.profilePicNotifier.value = cachedUrl;
    } else {
      AuthService.profilePicNotifier.value = null;
    }
  }

  void _startPremiumListener() {
    final user = AuthService().currentUser;
    if (user == null || user.isAnonymous) return;
    _profileSub = FirestoreService().userProfileStream.listen((profile) {
      final isPremium = profile?['isPremium'] == true;
      PreferencesService.setPremium(isPremium);
      if (mounted && _isPremium != isPremium) {
        setState(() => _isPremium = isPremium);
      }
    });
  }

  void _loadDashboardData() {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        final workersList = DummyData.workers;
        _totalWorkersCount = workersList.length;
        int mCount = 0;
        int fCount = 0;
        for (final w in workersList) {
          final genderStr = (w['gender'] ?? '').toString().trim().toLowerCase();
          if (genderStr == 'female') {
            fCount++;
          } else if (genderStr == 'male') {
            mCount++;
          }
        }
        _maleWorkersCount = mCount;
        _femaleWorkersCount = fCount;
        _workersList = List<Map<String, dynamic>>.from(workersList);

        // Guest: use all dummy attendance data (dummy data has no createdAt)
        _attendanceDocs = List<Map<String, dynamic>>.from(DummyData.attendance);

        _totalAttendanceCount = _attendanceDocs.length;
        _timeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _totalTimeoffCount = DummyData.timeoff.length;
        _recalculateDummyTotals(_selectedPeriod);
        _holidays = DummyData.holidays.values
            .expand((list) => list)
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } else {
      final firestore = FirestoreService();

      setState(() {
        _holidays = [];
      });

      _holidaysSub = firestore.holidaysStream.listen((snap) {
        if (mounted) {
          setState(() {
            _holidays = snap.docs.map((d) {
              return {...d.data() as Map<String, dynamic>, 'id': d.id};
            }).toList();
          });
        }
      });

      _workersSub = firestore.workersStream.listen((snap) {
        if (mounted) {
          int mCount = 0;
          int fCount = 0;
          final list = <Map<String, dynamic>>[];
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            list.add({...data, 'id': doc.id});
            final genderStr = (data['gender'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (genderStr == 'female') {
              fCount++;
            } else if (genderStr == 'male') {
              mCount++;
            }
          }
          setState(() {
            _workersList = list;
            _totalWorkersCount = snap.docs.length;
            _maleWorkersCount = mCount;
            _femaleWorkersCount = fCount;
          });
        }
      });

      _attendanceSub = firestore.attendanceStream.listen((snap) {
        if (mounted) {
          setState(() {
            final today = DateTime.now();
            _attendanceDocs = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .where((att) {
              final createdAt = att['createdAt'];
              if (createdAt == null) return false;
              DateTime? dt;
              if (createdAt is DateTime) {
                dt = createdAt;
              } else if (createdAt is String) {
                dt = DateTime.tryParse(createdAt);
              } else if (createdAt is Timestamp) {
                dt = createdAt.toDate();
              }
              return dt != null &&
                  dt.year == today.year &&
                  dt.month == today.month &&
                  dt.day == today.day;
            }).toList();
            _totalAttendanceCount = _attendanceDocs.length;
          });
        }
      });

      _timeoffSub = firestore.timeoffStream.listen((snap) {
        if (mounted) {
          setState(() {
            _timeoffDocs = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _totalTimeoffCount = snap.docs.length;
          });
        }
      });

      _expensesSub = firestore.expensesStream.listen((snap) {
        if (mounted) {
          setState(() {
            _rawExpensesDocs = snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              return {
                'id': doc.id,
                'amount': (data?['amount'] ?? 0.0) as num,
                'date': (data?['date'] ?? '') as String,
              };
            }).toList();
            _recalculateSumsForPeriod(_selectedPeriod);
          });
        }
      });

      _payrollSub = firestore.payrollStream.listen((snap) {
        if (mounted) {
          setState(() {
            _rawPayrollDocs = snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              final result = PayrollService.calculatePayroll(
                salary: (data?['salary'] ?? '').toString(),
                totalWorkDays: (data?['totalWorkDays'] ?? '').toString(),
                absents: (data?['absents'] ?? '').toString(),
                leaves: (data?['leaves'] ?? '').toString(),
                overtimeDays: (data?['overtimeDays'] ?? '').toString(),
              );
              return {
                'id': doc.id,
                'netSalary': result['netSalary'] as double,
                'date': (data?['date'] ?? '') as String,
              };
            }).toList();
            _recalculateSumsForPeriod(_selectedPeriod);
          });
        }
      });

      _notifSub = firestore.notificationsStream.listen((snap) {
        if (mounted) {
          setState(() {
            _unreadNotifCount = snap.docs.where((d) {
              final data = d.data() as Map<String, dynamic>?;
              return data?['isRead'] != true;
            }).length;
          });
        }
      });
    }
  }

  void _handlePeriodChanged(String period) {
    setState(() {
      _selectedPeriod = period;
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        _recalculateDummyTotals(period);
      } else {
        _recalculateSumsForPeriod(period);
      }
    });
  }

  void _recalculateSumsForPeriod(String period) {
    final now = DateTime.now();
    DateTime? dateLimit;
    if (period == 'Today') {
      dateLimit = DateTime(now.year, now.month, now.day);
    } else if (period == 'Week') {
      dateLimit = now.subtract(const Duration(days: 7));
    } else if (period == 'Month') {
      dateLimit = now.subtract(const Duration(days: 30));
    } else if (period == '6 Month') {
      dateLimit = now.subtract(const Duration(days: 180));
    } else if (period == 'Yearly') {
      dateLimit = now.subtract(const Duration(days: 365));
    }

    _totalExpensesSum = 0.0;
    for (final doc in _rawExpensesDocs) {
      if (dateLimit != null) {
        final dateStr = (doc['date'] ?? '').toString();
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          final docDate = DateTime(
            int.tryParse(parts[2]) ?? 0,
            int.tryParse(parts[1]) ?? 0,
            int.tryParse(parts[0]) ?? 0,
          );
          if (docDate.isBefore(dateLimit)) {
            continue;
          }
        }
      }
      _totalExpensesSum += (doc['amount'] as num).toDouble();
    }

    _totalSalarySum = 0.0;

    // Collect emails that already have payroll records
    final Set<String> payrollEmails = {};
    for (final doc in _rawPayrollDocs) {
      final email = (doc['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) payrollEmails.add(email);
    }

    // Add salary from payroll records
    for (final doc in _rawPayrollDocs) {
      if (dateLimit != null) {
        final dateStr = (doc['date'] ?? '').toString();
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          final docDate = DateTime(
            int.tryParse(parts[2]) ?? 0,
            int.tryParse(parts[1]) ?? 0,
            int.tryParse(parts[0]) ?? 0,
          );
          if (docDate.isBefore(dateLimit)) {
            continue;
          }
        }
      }
      _totalSalarySum += doc['netSalary'] as double;
    }


  }

  void _recalculateDummyTotals(String period) {
    double scale = 1.0;
    if (period == 'Today')
      scale = 0.02;
    else if (period == 'Week')
      scale = 0.05;
    else if (period == 'Month')
      scale = 0.2;
    else if (period == '6 Month')
      scale = 0.75;
    else if (period == 'Yearly')
      scale = 1.0;

    _totalExpensesSum =
        DummyData.expenses.fold(0.0, (sum, item) {
          return sum + ((item['amount'] ?? 0.0) as num).toDouble();
        }) *
        scale;

    _totalSalarySum =
        DummyData.payroll.fold(0.0, (sum, item) {
          final result = PayrollService.calculatePayroll(
            salary: (item['salary'] ?? '').toString(),
            totalWorkDays: (item['totalWorkDays'] ?? '').toString(),
            absents: (item['absents'] ?? '').toString(),
            leaves: (item['leaves'] ?? '').toString(),
            overtimeDays: (item['overtimeDays'] ?? '').toString(),
          );
          return sum + (result['netSalary'] as double);
        }) *
        scale;
  }

  void _handleLogout() {
    showLogoutDialog(context);
  }

  void _handleBackToLogin() async {
    await AuthService().signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _openProfile() {
    setState(() {
      _showProfile = true;
      _showNotifications = false;
    });
  }


  void _toggleNotifications() {
    final willShow = !_showNotifications;
    setState(() {
      _showNotifications = willShow;
    });
    if (willShow) {
      FirestoreService().markAllNotificationsRead();
    }
  }

  void _handleNotificationNavigation(String type) {
    setState(() {
      _showNotifications = false;
      switch (type) {
        case 'worker_added':
          _selectedIndex = 1;
          break;
        case 'attendance_marked':
          _selectedIndex = 2;
          _selectedSubIndex = 0;
          break;
        case 'payroll_added':
          _selectedIndex = 2;
          _selectedSubIndex = 1;
          break;
        case 'time_off_added':
          _selectedIndex = 2;
          _selectedSubIndex = 2;
          break;
        case 'asset_added':
          _selectedIndex = 2;
          _selectedSubIndex = 3;
          break;
        case 'holiday_added':
          _selectedIndex = 2;
          _selectedSubIndex = 4;
          break;
        case 'expense_added':
          _selectedIndex = 3;
          break;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const double minWidth = 1200;
          final double bodyWidth = constraints.maxWidth < minWidth
              ? minWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: bodyWidth,
              height: constraints.maxHeight,
              child: Row(
                children: [
                  SidebarWidget(
                    key: ValueKey('sidebar_${context.locale.languageCode}'),
                    selectedIndex: _showProfile ? -1 : _selectedIndex,
                    selectedSubIndex: _selectedSubIndex,
                    isGuest: AuthService().currentUser?.isAnonymous ?? false,
                    isPremium: _isPremium,
                    onItemSelected: (index, {subIndex}) => setState(() {
                      _selectedIndex = index;
                      _activatedScreens[index] = true;
                      if (subIndex != null) {
                        _selectedSubIndex = subIndex;
                      }
                      _showProfile = false;
                      _showWorkersAttendance = false;
                      _showAssignTimeOff = false;
                      _showNotifications = false;
                      _selectedTimeOffWorker = null;
                    }),
                    onBackToLogin: _handleBackToLogin,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Builder(
                          builder: (context) {
                            final int stackIndex = _getStackIndex();
                            return IndexedStack(
                              index: stackIndex,
                              children: [
                                // 0: Dashboard View
                                _activatedScreens[0]
                                    ? (_dashboardReady
                                        ? TweenAnimationBuilder<double>(
                                            key: ValueKey(stackIndex == 0),
                                            tween: Tween<double>(begin: 0, end: 1),
                                            duration: const Duration(
                                              milliseconds: 650,
                                            ),
                                            curve: Curves.easeOutQuart,
                                            builder: (context, value, child) {
                                              return Opacity(
                                                opacity: value,
                                                child: Transform.translate(
                                                  offset: Offset(
                                                    0,
                                                    15 * (1 - value),
                                                  ),
                                                  child: child,
                                                ),
                                              );
                                            },
                                            child: _buildDashboardView(),
                                          )
                                        : Column(
                                            children: [
                                              TopHeader(
                                                onProfileTap: _openProfile,
                                                onNotificationTap:
                                                    _toggleNotifications,
                                                unreadCount: _unreadNotifCount,
                                              ),
                                              const Expanded(
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                            ],
                                          ))
                                    : const SizedBox.shrink(),
                                // 1: Workers Screen
                                _getScreen(1),
                                // 2: Attendance Screen
                                _getScreen(2),
                                // 3: Payroll Screen
                                _getScreen(3),
                                // 4: Time Off Screen
                                _getScreen(4),
                                // 5: Assets Screen
                                _getScreen(5),
                                // 6: Holidays Screen
                                _getScreen(6),
                                // 7: Expenses Screen
                                _getScreen(7),
                                // 8: Settings Screen
                                _getScreen(8),
                                // 9: Assign Time Off
                                _getScreen(9),
                                // 10: Profile View
                                _buildProfileView(stackIndex == 10),
                                // 11: Workers Attendance Screen
                                WorkersAttendanceScreen(
                                  hideSidebar: true,
                                  onBack: () {
                                    setState(() {
                                      _showWorkersAttendance = false;
                                    });
                                  },
                                  onNotificationTap: _toggleNotifications,
                                ),
                              ],
                            );
                          },
                        ),
                        if (_showNotifications)
                          NotificationSidebar(
                            onClose: _toggleNotifications,
                            onNotificationTap: _handleNotificationNavigation,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboardView() {
    return Column(
      children: [
        TopHeader(
          onProfileTap: _openProfile,
          onNotificationTap: _toggleNotifications,
          unreadCount: _unreadNotifCount,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 40.0,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'dashboard'.tr(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 220,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TotalWorkersCard(
                          count: _totalWorkersCount,
                          maleCount: _maleWorkersCount,
                          femaleCount: _femaleWorkersCount,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SparklineCard(
                          title: 'total_salary'.tr(),
                          amount:
                              '\$${NumberFormat.compact(locale: 'en_US').format(_totalSalarySum.clamp(0, double.infinity))}',
                          rawValue: _totalSalarySum,
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF4C84E0),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SparklineCard(
                          title: 'expenses'.tr(),
                          amount:
                              '\$${NumberFormat.compact(locale: 'en_US').format(_totalExpensesSum)}',
                          rawValue: _totalExpensesSum,
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF0EA5E9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'attendance_overview'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'leave_types'.tr(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          CustomTimeframeDropdown(
                            selectedPeriod: _selectedPeriod,
                            onChanged: _handlePeriodChanged,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final double screenWidth = MediaQuery.of(
                      context,
                    ).size.width;
                    final bool isNarrow = screenWidth < 1150;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Transform.translate(
                            offset: const Offset(-10, 0),
                            child: AttendanceLineChart(
                              period: _selectedPeriod,
                              isEmpty:
                                  _totalAttendanceCount == 0 ||
                                  _totalWorkersCount == 0,
                              attendanceDocs: _attendanceDocs,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LeaveTypesPieChart(
                            period: _selectedPeriod,
                            isEmpty:
                                _totalTimeoffCount == 0 ||
                                _totalWorkersCount == 0,
                            timeoffDocs: _timeoffDocs,
                            workersList: _workersList,
                          ),
                        ],
                      );
                    } else {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Transform.translate(
                                offset: const Offset(-10, 0),
                                child: AttendanceLineChart(
                                  period: _selectedPeriod,
                                  isEmpty:
                                      _totalAttendanceCount == 0 ||
                                      _totalWorkersCount == 0,
                                  attendanceDocs: _attendanceDocs,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: LeaveTypesPieChart(
                                period: _selectedPeriod,
                                isEmpty:
                                    _totalTimeoffCount == 0 ||
                                    _totalWorkersCount == 0,
                                timeoffDocs: _timeoffDocs,
                                workersList: _workersList,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),

                // ==========================================
                // TOP HEADER SECTION (UPCOMING HOLIDAYS)
                // ==========================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'upcoming_holidays'.tr(),
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ==========================================
                // MAIN WHITE CONTAINER
                // ==========================================
                Builder(
                  builder: (context) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFFFFFF).withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                      child: () {
                        final now = DateTime.now();
                        final activeHolidays = _holidays.where((h) {
                          if (h['isEnabled'] != true) return false;

                          // Build holiday date from month and day fields
                          final monthStr = (h['month'] ?? '').toString();
                          final dayStr = (h['day'] ?? '').toString();
                          if (monthStr.isEmpty || dayStr.isEmpty) return false;

                          final monthNum = AppDateUtils.parseMonth(monthStr);
                          if (monthNum == null) return false;
                          final dayNum = int.tryParse(dayStr);
                          if (dayNum == null) return false;

                          // Build holiday date (use next year if already passed this year)
                          var holidayDate = DateTime(
                            now.year,
                            monthNum,
                            dayNum,
                          );
                          if (holidayDate.isBefore(
                            now.subtract(const Duration(days: 1)),
                          )) {
                            holidayDate = DateTime(
                              now.year + 1,
                              monthNum,
                              dayNum,
                            );
                          }

                          final daysUntilHoliday = holidayDate
                              .difference(now)
                              .inDays;
                          if (daysUntilHoliday < 0) return false;

                          switch (_selectedPeriod) {
                            case 'Week':
                              return daysUntilHoliday <= 7;
                            case 'Month':
                              return daysUntilHoliday <= 30;
                            case '6 Month':
                              return daysUntilHoliday <= 180;
                            case 'Yearly':
                            default:
                              return true;
                          }
                        }).toList();

                        for (final h in activeHolidays) {
                          final daysUntil = _daysUntilHoliday(h, now);
                          h['remainingDays'] = daysUntil != null
                              ? daysUntil.toString()
                              : (h['remainingDays']?.toString() ?? '0');
                        }
                        activeHolidays.sort((a, b) {
                          final aDays =
                              int.tryParse(
                                a['remainingDays']?.toString() ?? '',
                              ) ??
                              9999;
                          final bDays =
                              int.tryParse(
                                b['remainingDays']?.toString() ?? '',
                              ) ??
                              9999;
                          return aDays.compareTo(bDays);
                        });
                        if (activeHolidays.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/holidays_icon.svg',
                                    height: 50,
                                    width: 50,
                                    colorFilter: const ColorFilter.mode(
                                      Color(0xFF9CA3AF),
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'no_holidays_yet'.tr(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF9CA3AF),
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'overview'.tr(),
                              style: const TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 24),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                double spacing = 16.0;
                                double itemWidth =
                                    (constraints.maxWidth - (spacing * 4)) / 5;

                                return Wrap(
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: activeHolidays.map((h) {
                                    final remainingDaysStr =
                                        h['remainingDays'] ?? '';
                                    final remainingDaysInt =
                                        int.tryParse(remainingDaysStr) ?? -1;
                                    final isUrgent =
                                        remainingDaysInt >= 0 &&
                                        remainingDaysInt <= 5;

                                    return SizedBox(
                                      width: itemWidth,
                                      child: HolidayCard(
                                        day: h['day'] != null
                                            ? '${h['day']}'.padLeft(2, '0')
                                            : '',
                                        month: h['month'] ?? 'May',
                                        remainingDays: h['remainingDays'] ?? '',
                                        dayOfWeek: h['dayOfWeek'] ?? '',
                                        holidayName: h['name'] ?? '',
                                        isActive: isUrgent,
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        );
                      }(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileView(bool isActive) {
    return Column(
      children: [
        ProfileInlineHeader(
          onLogout: _handleLogout,
          onNotificationTap: _toggleNotifications,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
            child: ProfileBody(isActive: isActive),
          ),
        ),
      ],
    );
  }
}

int? _daysUntilHoliday(Map<String, dynamic> h, DateTime now) {
  final monthStr = (h['month'] ?? '').toString();
  final dayStr = (h['day'] ?? '').toString();
  if (monthStr.isEmpty || dayStr.isEmpty) return null;
  final monthNum = AppDateUtils.parseMonth(monthStr);
  final dayNum = int.tryParse(dayStr);
  if (monthNum == null || dayNum == null) return null;
  var holidayDate = DateTime(now.year, monthNum, dayNum);
  if (holidayDate.isBefore(now.subtract(const Duration(days: 1)))) {
    holidayDate = DateTime(now.year + 1, monthNum, dayNum);
  }
  final daysUntil = holidayDate.difference(now).inDays;
  return daysUntil >= 0 ? daysUntil : null;
}
