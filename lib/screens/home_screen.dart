import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';

import 'workers.dart';
import 'pricing_screen.dart';
import 'attendance_screen.dart';
import 'payroll_screen.dart';
import 'time_off.dart';
import 'assign_time_off.dart';
import 'assets_screen.dart';
import 'holidays_screen.dart';
import 'expenses_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import '../utils/logout_dialog.dart';
import 'login_screen.dart';
import '../services/dummy_data.dart';
import '../widgets/custom_timeframe_dropdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _selectedSubIndex = 0;
  String _selectedPeriod = 'Yearly';
  bool _showProfile = false;
  bool _showAssignTimeOff = false;
  final List<bool> _activatedScreens = List.filled(11, false);
  final Map<int, Widget> _screenCache = {};

  Widget _getScreen(int index) {
    if (!_activatedScreens[index]) {
      return const SizedBox.shrink();
    }
    return _screenCache.putIfAbsent(index, () {
      switch (index) {
        case 1:
          return WorkersScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onNotificationTap: _navigateToAttendance,
          );
        case 2:
          return AttendanceScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onNotificationTap: _navigateToAttendance,
          );
        case 3:
          return PayrollScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onAssignTimeOff: () {
              setState(() {
                _showAssignTimeOff = true;
              });
            },
            onNotificationTap: _navigateToAttendance,
          );
        case 4:
          return TimeOffScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onAssignTimeOff: () {
              setState(() {
                _showAssignTimeOff = true;
              });
            },
            onNotificationTap: _navigateToAttendance,
          );
        case 5:
          return AssetsScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onNotificationTap: _navigateToAttendance,
          );
        case 6:
          return HolidaysScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onNotificationTap: _navigateToAttendance,
          );
        case 7:
          return ExpensesScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            onNotificationTap: _navigateToAttendance,
          );
        case 8:
          return SettingsScreen(
            onLogout: _handleLogout,
            onProfileTap: _openProfile,
            isGuest: AuthService().currentUser?.isAnonymous ?? false,
            onNotificationTap: _navigateToAttendance,
          );
        case 9:
          return AssignTimeOffScreen(
            onBack: () => setState(() => _showAssignTimeOff = false),
            onNotificationTap: _navigateToAttendance,
          );
        default:
          return const SizedBox.shrink();
      }
    });
  }

  int _getStackIndex() {
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
  double _totalExpensesSum = 0.0;
  double _totalSalarySum = 0.0;
  List<Map<String, dynamic>> _holidays = [];
  StreamSubscription? _holidaysSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _expensesSub;
  StreamSubscription? _payrollSub;

  @override
  void dispose() {
    _holidaysSub?.cancel();
    _workersSub?.cancel();
    _expensesSub?.cancel();
    _payrollSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    AuthService.profilePicNotifier.value = AuthService().currentUser?.photoURL;
    _selectedIndex = 0;
    _loadDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPremiumAndShowDialog();
    });
  }

  void _loadDashboardData() {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      final now = DateTime.now();
      final currentMonthLong = DateFormat('MMMM').format(now);
      final currentMonthShort = DateFormat('MMM').format(now);
      String targetKey = 'May';
      for (final key in DummyData.holidays.keys) {
        if (key.toLowerCase() == currentMonthLong.toLowerCase() ||
            key.toLowerCase() == currentMonthShort.toLowerCase()) {
          targetKey = key;
          break;
        }
      }
      setState(() {
        _totalWorkersCount = DummyData.workers.length;
        _recalculateDummyTotals(_selectedPeriod);
        _holidays = (DummyData.holidays[targetKey] ?? [])
            .cast<Map<String, dynamic>>();
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
          setState(() {
            _totalWorkersCount = snap.docs.length;
          });
        }
      });

      _expensesSub = firestore.expensesStream.listen((snap) {
        if (mounted) {
          setState(() {
            _totalExpensesSum = snap.docs.fold(0.0, (sum, doc) {
              final data = doc.data() as Map<String, dynamic>?;
              return sum + ((data?['amount'] ?? 0.0) as num).toDouble();
            });
          });
        }
      });

      _payrollSub = firestore.payrollStream.listen((snap) {
        if (mounted) {
          setState(() {
            _totalSalarySum = snap.docs.fold(0.0, (sum, doc) {
              final data = doc.data() as Map<String, dynamic>?;
              final salaryStr = (data?['salary'] ?? '')
                  .toString()
                  .replaceAll('\$', '')
                  .replaceAll(',', '')
                  .trim();
              return sum + (double.tryParse(salaryStr) ?? 0.0);
            });
          });
        }
      });
    }
  }

  Future<void> _checkPremiumAndShowDialog() async {
    final isPremium = await PreferencesService.isPremium();
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isPremium && !isGuest && mounted) {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
        builder: (_) => const SubscriptionDialog(),
      );
    }
  }

  void _handlePeriodChanged(String period) {
    setState(() {
      _selectedPeriod = period;
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        _recalculateDummyTotals(period);
      }
    });
  }

  void _recalculateDummyTotals(String period) {
    double scale = 1.0;
    if (period == 'Week')
      scale = 0.05;
    else if (period == 'Month')
      scale = 0.2;
    else if (period == '3 Month')
      scale = 0.5;
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
          final salaryStr = (item['salary'] ?? '')
              .toString()
              .replaceAll('\$', '')
              .replaceAll(',', '')
              .trim();
          return sum + (double.tryParse(salaryStr) ?? 0.0);
        }) *
        scale;
  }

  void _handleLogout() {
    showLogoutDialog(context);
  }

  void _handleBackToLogin() async {
    await AuthService().signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _openProfile() {
    setState(() => _showProfile = true);
  }

  void _navigateToAttendance() {
    setState(() {
      _selectedIndex = 2;
      _selectedSubIndex = 0;
      _showProfile = false;
      _showAssignTimeOff = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Row(
        children: [
          SidebarWidget(
            selectedIndex: _showProfile ? -1 : _selectedIndex,
            selectedSubIndex: _selectedSubIndex,
            isGuest: AuthService().currentUser?.isAnonymous ?? false,
            onItemSelected: (index, {subIndex}) => setState(() {
              _selectedIndex = index;
              if (subIndex != null) {
                _selectedSubIndex = subIndex;
              }
              _showProfile = false;
              _showAssignTimeOff = false;
            }),
            onBackToLogin: _handleBackToLogin,
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final int stackIndex = _getStackIndex();
                _activatedScreens[stackIndex] = true;
                return IndexedStack(
                  index: stackIndex,
                  children: [
                    // 0: Dashboard View
                    _activatedScreens[0]
                        ? _buildDashboardView()
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
                    _activatedScreens[10]
                        ? _buildProfileView()
                        : const SizedBox.shrink(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardView() {
    return Column(
      children: [
        TopHeader(
          onProfileTap: _openProfile,
          onNotificationTap: _navigateToAttendance,
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
                  height: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TotalWorkersCard(count: _totalWorkersCount),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SparklineCard(
                          title: 'total_salary'.tr(),
                          amount:
                              '\$${NumberFormat.compact().format(_totalSalarySum)}',
                          period: _selectedPeriod,
                          lineColor: const Color(0xFF8BB1F3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SparklineCard(
                          title: 'expenses'.tr(),
                          amount:
                              '\$${NumberFormat.compact().format(_totalExpensesSum)}',
                          period: _selectedPeriod,
                          lineColor: const Color(0xFFAFE0FE),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
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
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: AttendanceLineChart(
                          period: _selectedPeriod,
                          isEmpty: _totalWorkersCount == 0,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: LeaveTypesPieChart(
                          period: _selectedPeriod,
                          isEmpty: _totalWorkersCount == 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

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
                    // Period Dropdown Button
                    CustomTimeframeDropdown(
                      selectedPeriod: _selectedPeriod,
                      onChanged: _handlePeriodChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ==========================================
                // MAIN WHITE CONTAINER
                // ==========================================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF000000).withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _holidays.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'overview'.tr(),
                              style: TextStyle(
                                color: Color(0xFF000000),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 24),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                double spacing = 10.0;
                                double itemWidth =
                                    (constraints.maxWidth - (spacing * 4)) / 5;

                                return Wrap(
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: _holidays.map((h) {
                                    final isActive = h['isEnabled'] == true;
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
                                        isActive: isActive,
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/holidays_icon.svg',
                                  height: 50,
                                  width: 50,
                                  color: const Color(0xFF9CA3AF),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'no_holidays_yet'.tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF9CA3AF),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileView() {
    return Column(
      children: [
        ProfileInlineHeader(
          onLogout: _handleLogout,
          onNotificationTap: _navigateToAttendance,
        ),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
            child: ProfileBody(),
          ),
        ),
      ],
    );
  }
}

class SidebarWidget extends StatefulWidget {
  final int selectedIndex;
  final int selectedSubIndex;
  final bool isGuest;
  final void Function(int index, {int? subIndex}) onItemSelected;
  final VoidCallback? onBackToLogin;

  const SidebarWidget({
    super.key,
    required this.selectedIndex,
    this.selectedSubIndex = 0,
    this.isGuest = false,
    required this.onItemSelected,
    this.onBackToLogin,
  });

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  bool _isWorkforceExpanded = false;

  @override
  void initState() {
    super.initState();
    _isWorkforceExpanded = widget.selectedIndex == 2;
  }

  @override
  void didUpdateWidget(covariant SidebarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == 2) {
      _isWorkforceExpanded = true;
    }
  }

  static final _menuItems = [
    ('assets/dashbaord_icon_slidebar.svg', 'sidebar_dashboard', false),
    ('assets/workers_icon_slidebar.svg', 'sidebar_workers', false),
    ('assets/workforce_icon_sldiebar.svg', 'sidebar_workforce', true),
    ('assets/expenses_icon_slidebar.svg', 'sidebar_expenses', false),
    ('assets/settings_icon_slidebar.svg', 'sidebar_settings', false),
  ];

  static final _subItems = [
    ('assets/total_salary.svg', 'sidebar_attendance'),
    ('assets/payroll_icon.svg', 'sidebar_payroll'),
    ('assets/time_off_icon.svg', 'sidebar_time_off'),
    ('assets/assets_icon.svg', 'sidebar_assets'),
    ('assets/holidays_icon.svg', 'sidebar_holidays'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: const Color(0xFF0247C4),
      child: Column(
        children: [
          if (!widget.isGuest)
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
                  builder: (context) => const SubscriptionDialog(),
                );
              },
              child: Container(
                width: 220,
                height: 181,
                margin: const EdgeInsets.only(top: 29, left: 19, right: 19),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Color(0xFFFFFFFF), width: 1.0),
                  image: const DecorationImage(
                    image: AssetImage('assets/premium_bg.png'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xFFFFFFFF),
                      blurRadius: 3.0,
                      spreadRadius: 0.0,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/premium_icon.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'upgrade_pro'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                            height: 1.0,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildCheckText('unlock_all_features'.tr()),
                    _buildCheckText('no_commitment'.tr()),
                    _buildCheckText('cancel_anytime'.tr()),
                    const SizedBox(height: 4),
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerRight,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 40,
                          padding: const EdgeInsets.only(left: 14, right: 46),
                          decoration: BoxDecoration(
                            color: Color(0xFF000000),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Color(0xFFFFFFFF),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'get_to_pro'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'SF Pro',
                                  height: 1.1,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'subscribe_now'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'SF Pro',
                                  height: 1.1,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: -6,
                          bottom: -6,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Image.asset(
                              "assets/right_back_arrow.png",
                              width: 16,
                              height: 16,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (int i = 0; i < _menuItems.length; i++)
                    if (_menuItems[i].$3)
                      _buildWorkforceItem(i)
                    else
                      _buildMenuItem(
                        _menuItems[i].$1,
                        _menuItems[i].$2.tr(),
                        isSelected: widget.selectedIndex == i,
                        hasDropdown: _menuItems[i].$3,
                        onTap: () {
                          widget.onItemSelected(i);
                        },
                      ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (widget.isGuest)
            Container(
              height: 42,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: GestureDetector(
                onTap: widget.onBackToLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_back,
                        color: Color(0xFFFFFFFF),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'back_to_login_sidebar'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkforceItem(int index) {
    if (_isWorkforceExpanded) {
      final isSelected = widget.selectedIndex == index;
      return Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF).withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                _buildWorkforceHeaderItem(
                  onTap: () {
                    setState(() {
                      _isWorkforceExpanded = false;
                    });
                  },
                ),
                const SizedBox(height: 4),
                for (int i = 0; i < _subItems.length; i++)
                  _buildSubMenuItem(
                    _subItems[i].$1,
                    _subItems[i].$2.tr(),
                    isSelected:
                        widget.selectedIndex == index &&
                        widget.selectedSubIndex == i,
                    onTap: () {
                      widget.onItemSelected(index, subIndex: i);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 11.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: 8,
              height: isSelected ? 32 : 0,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return _buildMenuItem(
        _menuItems[index].$1,
        _menuItems[index].$2.tr(),
        isSelected: widget.selectedIndex == index,
        hasDropdown: true,
        onTap: () {
          setState(() {
            _isWorkforceExpanded = true;
          });
          widget.onItemSelected(index);
        },
      );
    }
  }

  Widget _buildWorkforceHeaderItem({VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/workforce_icon_sldiebar.svg',
              height: 22,
              width: 22,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'sidebar_workforce'.tr(),
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFFFFFFFF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(
    String iconAsset,
    String title, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFFFFF).withValues(alpha: 0.36)
              : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconAsset,
              height: 20,
              width: 20,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w500,
                  fontFamily: 'SF Pro',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/tick_icon.svg',
            width: 14,
            height: 10,
            color: Color(0xFFFFFFFF),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    String iconAsset,
    String title, {
    bool isSelected = false,
    bool hasDropdown = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.36)
                  : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  iconAsset,
                  height: 22,
                  width: 22,
                  color: Color(0xFFFFFFFF),
                ),
                const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 18,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w500,
                  fontFamily: 'SF Pro',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasDropdown)
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFFFFFFFF),
                    size: 20,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: 8,
                height: isSelected ? 32 : 0,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TopHeader extends StatelessWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationTap;
  const TopHeader({
    super.key,
    required this.onProfileTap,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final name = user?.displayName ?? 'User';

    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEFF2))),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Welcome text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'welcome_user'.tr(namedArgs: {'name': name}),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'welcome_subtitle'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          // Right: notification + avatar
          Row(
            children: [
              // Notification bell
              GestureDetector(
                onTap: onNotificationTap,
                child: SvgPicture.asset(
                  'assets/notification_icon.svg',
                  width: 22,
                  height: 26,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF000000),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Profile avatar (clickable to open profile screen)
              GestureDetector(onTap: onProfileTap, child: const UserAvatar()),
            ],
          ),
        ],
      ),
    );
  }
}

class TotalWorkersCard extends StatelessWidget {
  final int count;
  const TotalWorkersCard({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: count > 0
            ? Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/workers_icon_slidebar.svg',
                            height: 22,
                            width: 22,
                            color: const Color(0xFF155ED5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'total_workers'.tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const RoundedDonutChart(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '60%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF000000),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                Text(
                                  'male'.tr(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 2),
                            Transform.rotate(
                              angle: 0.35,
                              child: Container(
                                width: 1,
                                height: 22,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '40%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF000000),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                Text(
                                  'female'.tr(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildLegendItem(
                        Color(0xFF155ED5),
                        'male'.tr(),
                        '380 Workers',
                      ),
                      _buildLegendItem(
                        Color(0xFFFF2D2D),
                        'female'.tr(),
                        '70 Workers',
                      ),
                    ],
                  ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/total_workers.svg',
                      height: 40,
                      width: 40,
                      color: const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'no_workers_added_yet'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String title, String subtitle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: CircleAvatar(radius: 4, backgroundColor: color),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'SF Pro Display',
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RoundedDonutChart extends StatelessWidget {
  const RoundedDonutChart({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        return CustomPaint(
          size: const Size(130, 130),
          painter: _DonutChartPainter(progress: value),
        );
      },
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double progress;

  _DonutChartPainter({this.progress = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width - 24) / 2; // radius to draw the center of the arc

    // Red Paint (40%)
    final redPaint = Paint()
      ..color = const Color(0xFFFF2D2D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Blue Paint (60%)
    final bluePaint = Paint()
      ..color = const Color(0xFF155ED5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Start angle is -45 degrees (-pi / 4)
    const double startAngle = -3.1415926535 / 4;
    const double redSweep = 0.40 * 2 * 3.1415926535;
    const double blueSweep = 0.60 * 2 * 3.1415926535;

    // Draw Red first
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      redSweep * progress,
      false,
      redPaint,
    );

    // Draw Blue second (overlaps red caps)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + redSweep * progress,
      blueSweep * progress,
      false,
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class SparklineCard extends StatelessWidget {
  final String title;
  final String amount;
  final String period;
  final Color lineColor;

  const SparklineCard({
    super.key,
    required this.title,
    required this.amount,
    required this.period,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = amount == '\$0';
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: !isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset(
                            lineColor == const Color(0xFF8BB1F3)
                                ? 'assets/total_salary.svg'
                                : 'assets/total_expense.svg',
                            height: 22,
                            width: 22,
                            color: const Color(0xFF155ED5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            amount,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          Text(
                            period,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOutCubic,
                      builder: (context, animValue, child) {
                        final double m = period == 'Week'
                            ? 0.3
                            : period == 'Month'
                            ? 0.6
                            : period == '3 Month'
                            ? 0.8
                            : period == '6 Month'
                            ? 0.9
                            : 1.0;
                        final spots = [
                          FlSpot(0, 3 * m),
                          FlSpot(1, 6 * m),
                          FlSpot(2, 4 * m),
                          FlSpot(3, 4 * m),
                          FlSpot(4, 7 * m),
                          FlSpot(5, 5 * m),
                          FlSpot(6, 6 * m),
                          FlSpot(7, 2 * m),
                          FlSpot(8, 7 * m),
                        ];
                        return LineChart(
                          LineChartData(
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (spot) =>
                                    const Color(0xFF2C3E50),
                                tooltipRoundedRadius: 8,
                                getTooltipItems: (spots) {
                                  return spots.map((spot) {
                                    return LineTooltipItem(
                                      spot.y.toStringAsFixed(0),
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            gridData: FlGridData(show: false),
                            titlesData: FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            minY: 0,
                            maxY: 10,
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots
                                    .map((s) => FlSpot(s.x, s.y * animValue))
                                    .toList(),
                                isCurved: true,
                                color: lineColor,
                                barWidth: 1,
                                isStrokeCapRound: true,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      lineColor.withValues(alpha: 0.3),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      lineColor == const Color(0xFF8BB1F3)
                          ? 'assets/total_salary.svg'
                          : 'assets/total_expense.svg',
                      height: 40,
                      width: 40,
                      color: const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lineColor == const Color(0xFF8BB1F3)
                          ? 'no_salary_records_yet'.tr()
                          : 'no_expenses_recorded_yet'.tr(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class AttendanceLineChart extends StatelessWidget {
  final String period;
  final bool isEmpty;

  const AttendanceLineChart({
    super.key,
    required this.period,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    period,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 300,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeInOutCubic,
                      builder: (context, animValue, child) {
                        final double m = period == 'Week'
                            ? 0.4
                            : period == 'Month'
                            ? 0.6
                            : period == '3 Month'
                            ? 0.8
                            : period == '6 Month'
                            ? 0.9
                            : 1.0;
                        final spots = [
                          FlSpot(0, 0),
                          FlSpot(1, 0.4 * m),
                          FlSpot(2, 1.8 * m),
                          FlSpot(3, 2.8 * m),
                          FlSpot(4, 2.4 * m),
                          FlSpot(5, 5 * m),
                          FlSpot(6, 7 * m),
                        ];
                        return LineChart(
                          LineChartData(
                            minX: 0,
                            maxX: 6,
                            minY: 0,
                            maxY: 7,
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (spot) =>
                                    const Color(0xFF2C3E50),
                                tooltipRoundedRadius: 8,
                                getTooltipItems: (spots) {
                                  return spots.map((spot) {
                                    return LineTooltipItem(
                                      spot.y.toStringAsFixed(0),
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawHorizontalLine: false,
                              drawVerticalLine: true,
                              getDrawingVerticalLine: (value) =>
                                  FlLine(color: Colors.black12, strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    const style = TextStyle(
                                      color: Color(0xFF155ED5),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SF Pro Display',
                                    );
                                    String text;
                                    switch (value.toInt()) {
                                      case 0:
                                        text = '0';
                                        break;
                                      case 1:
                                        text = '20';
                                        break;
                                      case 2:
                                        text = '40';
                                        break;
                                      case 3:
                                        text = '60';
                                        break;
                                      case 4:
                                        text = '80';
                                        break;
                                      case 5:
                                        text = '100';
                                        break;
                                      case 6:
                                        text = '120';
                                        break;
                                      case 7:
                                        text = '140';
                                        break;
                                      default:
                                        return Container();
                                    }
                                    return Text(text, style: style);
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    const style = TextStyle(
                                      color: Color(0xFF155ED5),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SF Pro Display',
                                    );
                                    String text;
                                    switch (value.toInt()) {
                                      case 0:
                                        text = 'JAN';
                                        break;
                                      case 1:
                                        text = 'FEB';
                                        break;
                                      case 2:
                                        text = 'MAR';
                                        break;
                                      case 3:
                                        text = 'APR';
                                        break;
                                      case 4:
                                        text = 'MAY';
                                        break;
                                      case 5:
                                        text = 'JUN';
                                        break;
                                      case 6:
                                        text = 'JUL';
                                        break;
                                      default:
                                        return Container();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: Text(text, style: style),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: const Border(
                                bottom: BorderSide(
                                  color: Colors.black,
                                  width: 1,
                                ),
                                left: BorderSide(color: Colors.black, width: 1),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots
                                    .map((s) => FlSpot(s.x, s.y * animValue))
                                    .toList(),
                                isCurved: false,
                                color: const Color(0xFF23447F),
                                barWidth: 2,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter:
                                      (spot, percent, barData, index) {
                                        return FlDotCirclePainter(
                                          radius: 4,
                                          color: const Color(0xFF23447F),
                                          strokeWidth: 0,
                                        );
                                      },
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: const Color(0xFFDFE6FA),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: 430,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/present_grey.svg',
                        height: 50,
                        width: 50,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'no_attendance_data_yet'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class LeavePeriodConfig {
  final double casualVal;
  final double sickVal;
  final double medicalVal;

  final List<Offset> casualPath;
  final List<Offset> sickPath;
  final List<Offset> medicalPath;

  final double? casualLeft;
  final double? casualTop;
  final double? casualRight;
  final double? casualBottom;

  final double? sickLeft;
  final double? sickTop;
  final double? sickRight;
  final double? sickBottom;

  final double? medicalLeft;
  final double? medicalTop;
  final double? medicalRight;
  final double? medicalBottom;

  const LeavePeriodConfig({
    required this.casualVal,
    required this.sickVal,
    required this.medicalVal,
    required this.casualPath,
    required this.sickPath,
    required this.medicalPath,
    this.casualLeft,
    this.casualTop,
    this.casualRight,
    this.casualBottom,
    this.sickLeft,
    this.sickTop,
    this.sickRight,
    this.sickBottom,
    this.medicalLeft,
    this.medicalTop,
    this.medicalRight,
    this.medicalBottom,
  });
}

class LeaveTypesPieChart extends StatelessWidget {
  final String period;
  final bool isEmpty;

  const LeaveTypesPieChart({
    super.key,
    required this.period,
    this.isEmpty = false,
  });

  static const Map<String, LeavePeriodConfig> _configs = {
    'Week': LeavePeriodConfig(
      casualVal: 60,
      sickVal: 15,
      medicalVal: 25,
      casualPath: [Offset(147, 116), Offset(97, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(230, 110), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(220, 160), Offset(170, 220), Offset(100, 220)],
      medicalLeft: 110,
      medicalBottom: 43,
    ),
    'Month': LeavePeriodConfig(
      casualVal: 50,
      sickVal: 20,
      medicalVal: 30,
      casualPath: [Offset(151, 107.5), Offset(105, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(226.4, 103.5), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(200, 165), Offset(170, 220), Offset(100, 220)],
      medicalLeft: 110,
      medicalBottom: 43,
    ),
    '3 Month': LeavePeriodConfig(
      casualVal: 45,
      sickVal: 25,
      medicalVal: 30,
      casualPath: [Offset(149, 111), Offset(101, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(222, 98), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(200, 165), Offset(170, 220), Offset(100, 220)],
      medicalLeft: 110,
      medicalBottom: 43,
    ),
    '6 Month': LeavePeriodConfig(
      casualVal: 40,
      sickVal: 30,
      medicalVal: 30,
      casualPath: [Offset(147, 114), Offset(98, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(212, 91), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(200, 165), Offset(170, 220), Offset(100, 220)],
      medicalLeft: 110,
      medicalBottom: 43,
    ),
    'Yearly': LeavePeriodConfig(
      casualVal: 35,
      sickVal: 35,
      medicalVal: 30,
      casualPath: [Offset(146, 118), Offset(95, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(205, 88), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(200, 165), Offset(170, 220), Offset(100, 220)],
      medicalLeft: 110,
      medicalBottom: 43,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final config = _configs[period] ?? _configs['Month']!;

    return Card(
      elevation: 0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    period,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOutCubic,
                    builder: (context, animValue, child) {
                      return Opacity(
                        opacity: animValue,
                        child: Transform.scale(scale: animValue, child: child),
                      );
                    },
                    child: Center(
                      child: SizedBox(
                        width: 380,
                        height: 260,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                sectionsSpace: 0.0,
                                centerSpaceRadius: 0,
                                startDegreeOffset:
                                    90, // Draw from 6 o'clock (Left half)
                                sections: [
                                  PieChartSectionData(
                                    color: const Color(
                                      0xFF84A9FF,
                                    ), // Casual Leave
                                    value: config.casualVal,
                                    radius: 85,
                                    showTitle: false,
                                  ),
                                  PieChartSectionData(
                                    color: const Color(
                                      0xFFFF4A5E,
                                    ), // Sick Leave
                                    value: config.sickVal,
                                    radius: 85,
                                    showTitle: false,
                                  ),
                                  PieChartSectionData(
                                    color: const Color(
                                      0xFF97FFA9,
                                    ), // Medical Leave
                                    value: config.medicalVal,
                                    radius: 85,
                                    showTitle: false,
                                  ),
                                ],
                              ),
                            ),
                            CustomPaint(
                              size: const Size(380, 260),
                              painter: CalloutLinesPainter(
                                casualPath: config.casualPath,
                                sickPath: config.sickPath,
                                medicalPath: config.medicalPath,
                              ),
                            ),
                            Positioned(
                              top: config.casualTop,
                              left: config.casualLeft,
                              right: config.casualRight,
                              bottom: config.casualBottom,
                              child: _ChartLabel(
                                '${config.casualVal.toInt()}%',
                              ),
                            ),
                            Positioned(
                              top: config.sickTop,
                              left: config.sickLeft,
                              right: config.sickRight,
                              bottom: config.sickBottom,
                              child: _ChartLabel('${config.sickVal.toInt()}%'),
                            ),
                            Positioned(
                              top: config.medicalTop,
                              left: config.medicalLeft,
                              right: config.medicalRight,
                              bottom: config.medicalBottom,
                              child: _ChartLabel(
                                '${config.medicalVal.toInt()}%',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFF84A9FF),
                                'Casual Leave: ${config.casualVal.toInt()}%',
                              ),
                            ),
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFFFF4A5E),
                                'Sick Leave: ${config.sickVal.toInt()}%',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildLegendItem(
                                const Color(0xFF97FFA9),
                                'Medical Leave: ${config.medicalVal.toInt()}%',
                              ),
                            ),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: 430,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/leave_grey.svg',
                        height: 50,
                        width: 50,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'no_leave_data_yet'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }
}

class _ChartLabel extends StatelessWidget {
  final String text;
  const _ChartLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
    );
  }
}

class CalloutLinesPainter extends CustomPainter {
  final List<Offset> casualPath;
  final List<Offset> sickPath;
  final List<Offset> medicalPath;

  CalloutLinesPainter({
    required this.casualPath,
    required this.sickPath,
    required this.medicalPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawOffsetPath(canvas, paint, casualPath);
    _drawOffsetPath(canvas, paint, sickPath);
    _drawOffsetPath(canvas, paint, medicalPath);
  }

  void _drawOffsetPath(Canvas canvas, Paint paint, List<Offset> points) {
    if (points.length < 2) return;
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CalloutLinesPainter oldDelegate) {
    return oldDelegate.casualPath != casualPath ||
        oldDelegate.sickPath != sickPath ||
        oldDelegate.medicalPath != medicalPath;
  }
}

// ==========================================
// REUSABLE CUSTOM HOLIDAY CARD WIDGET
// ==========================================
class HolidayCard extends StatelessWidget {
  final String day;
  final String month;
  final String remainingDays;
  final String dayOfWeek;
  final String holidayName;
  final bool isActive;

  const HolidayCard({
    super.key,
    required this.day,
    required this.month,
    required this.remainingDays,
    required this.dayOfWeek,
    required this.holidayName,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    // Define exact colors based on state

    // Active (Red) State Colors
    final Color activeLeftBg = const Color(0xFFFA6668); // Soft coral red
    final Color activeRightBg = const Color(0xFFFF0000); // Pure bright red
    final Color activeTextColor = Color(0xFFFFFFFF);
    final Color activeSubTextColor = Color(0xFFFFFFFF).withValues(alpha: 0.9);
    final Color activeBadgeBg = const Color(0xFFFA6668); // Matches left bg

    // Inactive (Grey) State Colors
    final Color inactiveLeftBg = const Color(0xFFE2E4E4); // Darker grey left
    final Color inactiveRightBg = const Color(0xFFF1F1F1); // Lighter grey right
    final Color inactiveTextColor = Color(0xFF000000);
    final Color inactiveSubTextColor = Colors.black;
    final Color inactiveBadgeBg = const Color(0xFF4C84E0); // Blue badge

    // Assign chosen colors
    Color leftBg = isActive ? activeLeftBg : inactiveLeftBg;
    Color rightBg = isActive ? activeRightBg : inactiveRightBg;
    Color mainTextColor = isActive ? activeTextColor : inactiveTextColor;
    Color subTextColor = isActive ? activeSubTextColor : inactiveSubTextColor;
    Color badgeBg = isActive ? activeBadgeBg : inactiveBadgeBg;

    return Container(
      height: 115,
      clipBehavior: Clip.antiAlias, // Ensures corners clip contents
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          // --- Left Side (Date) ---
          Container(
            width: 50, // Reduced from 55 to give more horizontal room for text
            color: leftBg,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 18, // Reduced from 20
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  month,
                  style: TextStyle(
                    color: mainTextColor,
                    fontSize: 12, // Reduced from 14
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),

          // --- Right Side (Details) ---
          Expanded(
            child: Container(
              color: rightBg,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Top Row: Remaining Days
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Remaining Days',
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                            height: 1.0,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 20,
                        child: Text(
                          remainingDays,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: mainTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const SizedBox(height: 2),
                  // Middle: Day Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dayOfWeek,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Bottom: Holiday Name
                  Text(
                    holidayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mainTextColor,
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
