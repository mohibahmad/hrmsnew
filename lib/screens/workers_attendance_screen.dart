import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/preferences_service.dart';
import '../widgets/sidebar_widget.dart';
import '../utils/snackbar_utils.dart';
import '../utils/image_utils.dart';
import '../utils/date_utils.dart' as app_date_utils;
import '../utils/leave_balance_helper.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'home_screen.dart';

const Color primaryBlue = Color(0xFF0B51C1);
const Color bgGray = Color(0xFFF7F8FA);
const Color cardLightGray = Color(0xFFF3F5F8);
const Color textDark = Color(0xFF000000);
const Color textMuted = Color(0xFF64748B);

const Color greenPresent = Color(0xFF00FF2A);
const Color redAbsent = Color(0xFFFF0004);
const Color orangeLeave = Color(0xFFFF7B00);
const Color pillGray = Color(0xFFE2E5EA);

class WorkersAttendanceScreen extends StatefulWidget {
  final VoidCallback? onNotificationTap;
  final bool hideSidebar;
  final VoidCallback? onBack;
  const WorkersAttendanceScreen({
    super.key,
    this.onNotificationTap,
    this.hideSidebar = false,
    this.onBack,
  });

  @override
  State<WorkersAttendanceScreen> createState() =>
      _WorkersAttendanceScreenState();
}

class _WorkersAttendanceScreenState extends State<WorkersAttendanceScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  String _selectedTimeframe = 'Today';
  int _currentPage = 1;
  static const int _itemsPerPage = 10;
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _todayAttendance = [];
  List<Map<String, dynamic>> _holidays = [];
  bool _isLoading = true;
  bool _workersLoaded = false;
  bool _attendanceLoaded = false;
  bool _isDialogOpen = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isPremium = false;
  final FirestoreService _firestore = FirestoreService();
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _holidaysSub;

  @override
  void dispose() {
    _workersSub?.cancel();
    _attendanceSub?.cancel();
    _holidaysSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final currentUser = AuthService().currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      _firestore
          .getUserProfile()
          .then((profile) {
            if (profile != null && mounted) {
              final pic = profile['profilePic'];
              if (pic != null && pic.toString().isNotEmpty) {
                AuthService.profilePicNotifier.value = pic.toString();
              }
            }
          })
          .catchError((_) {});
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _workers = List<Map<String, dynamic>>.from(DummyData.workers);
        _todayAttendance = _latestAttendancePerWorker(
          List<Map<String, dynamic>>.from(DummyData.attendance),
        );
        _holidays = DummyData.holidays.values
            .expand((l) => l)
            .cast<Map<String, dynamic>>()
            .toList();
        _isLoading = false;
      });
      return;
    }

    final user = AuthService().currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final profile = await _firestore.getUserProfile();
        if (mounted) {
          setState(() {
            _isPremium = profile?['isPremium'] == true;
          });
        }
      } catch (_) {
        final prefsPremium = await PreferencesService.isPremium();
        if (mounted) {
          setState(() {
            _isPremium = prefsPremium;
          });
        }
      }
    }

    _workersSub = _firestore.workersStream.listen(
      (snapshot) {
        if (mounted) {
          setState(() {
            _workers = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _workersLoaded = true;
            if (_workersLoaded && _attendanceLoaded) _isLoading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      },
    );
    _attendanceSub = _firestore.attendanceStream.listen(
      (snapshot) {
        if (mounted) {
          setState(() {
            final sortedList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            sortedList.sort((a, b) {
              final aTime = a['createdAt'];
              final bTime = b['createdAt'];
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return -1;
              if (bTime == null) return 1;
              if (aTime is Timestamp && bTime is Timestamp) {
                return bTime.compareTo(aTime);
              }
              return 0;
            });
            final filtered = sortedList.where((att) {
              return app_date_utils.AppDateUtils.isTimestampWithinPeriod(
                att['createdAt'],
                _selectedTimeframe,
              );
            }).toList();
            _todayAttendance = _latestAttendancePerWorker(filtered);
            _attendanceLoaded = true;
            if (_workersLoaded && _attendanceLoaded) _isLoading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      },
    );

    _holidaysSub = _firestore.holidaysStream.listen(
      (snap) {
        if (mounted) {
          setState(() {
            _holidays = snap.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
          });
        }
      },
      onError: (_) {},
    );
  }

  String _getWorkerStatus(Map<String, dynamic> worker) {
    final directStatus = worker["status"]?.toString();
    if (directStatus != null &&
        directStatus.isNotEmpty &&
        directStatus != "*****") {
      return directStatus;
    }
    // Derive status from today's attendance records
    final email = worker["email"]?.toString() ?? "";
    final attRecord = _todayAttendance.cast<Map<String, dynamic>?>().firstWhere(
      (att) => att?['email']?.toString() == email,
      orElse: () => null,
    );
    if (attRecord != null) {
      final attStatus = attRecord['status']?.toString() ?? "";
      if (attStatus.isNotEmpty && attStatus != "*****") {
        return attStatus;
      }
    }
    return "";
  }

  DateTime? _attendanceDate(dynamic createdAt) {
    if (createdAt == null) return null;
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is DateTime) return createdAt;
    if (createdAt is String) return DateTime.tryParse(createdAt);
    return null;
  }

  // Returns the holiday record if today's date matches an enabled holiday.
  Map<String, dynamic>? get _todayHoliday {
    final now = DateTime.now();
    for (final h in _holidays) {
      if (h['isEnabled'] != true) continue;
      final monthNum = app_date_utils.AppDateUtils.parseMonth(
        (h['month'] ?? '').toString(),
      );
      final dayNum = int.tryParse((h['day'] ?? '').toString());
      if (monthNum == now.month && dayNum == now.day) return h;
    }
    return null;
  }

  // Keeps only the most recent attendance record per worker email so that an
  // older "Absent" record can't linger next to a newer "Leave" record.
  List<Map<String, dynamic>> _latestAttendancePerWorker(
    List<Map<String, dynamic>> records,
  ) {
    final byEmail = <String, Map<String, dynamic>>{};
    for (final att in records) {
      final email = (att['email'] ?? '').toString().toLowerCase();
      if (email.isEmpty) continue;
      final existing = byEmail[email];
      if (existing == null) {
        byEmail[email] = att;
        continue;
      }
      final da = _attendanceDate(att['createdAt']);
      final db = _attendanceDate(existing['createdAt']);
      final isNewer =
          da != null &&
          (db == null ||
              da.isAfter(db) ||
              (da.isAtSameMomentAs(db) &&
                  (att['id'] ?? '').toString().compareTo(
                        (existing['id'] ?? '').toString(),
                      ) >
                      0));
      if (isNewer) byEmail[email] = att;
    }
    return byEmail.values.toList();
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    return _workers.where((worker) {
      final name = (worker["name"] ?? "").toString().toLowerCase();
      final role = (worker["position"] ?? worker["role"] ?? "")
          .toString()
          .toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || role.contains(query);
      if (_selectedStatusFilter == 'All') return matchesSearch;
      final workerStatus = _getWorkerStatus(worker);
      return matchesSearch && workerStatus == _selectedStatusFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final holiday = _todayHoliday;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: bgGray,
        body: Center(child: CircularProgressIndicator(color: primaryBlue)),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: bgGray,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'error_occurred'.tr(namedArgs: {'error': _errorMessage!}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textDark,
                fontSize: 15,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgGray,
      resizeToAvoidBottomInset: false,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Sidebar (Standard SidebarWidget) - hide when embedded in HomeScreen
          if (!widget.hideSidebar)
            SidebarWidget(
              key: ValueKey('sidebar_${context.locale.languageCode}'),
              selectedIndex: 2,
              selectedSubIndex: 0,
              isGuest: AuthService().currentUser?.isAnonymous ?? false,
              isPremium: _isPremium,
              onItemSelected: (index, {subIndex}) {
                _isDialogOpen = false;
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => HomeScreen(
                      initialIndex: index == 2 ? 2 : index,
                      initialSubIndex: index == 2 ? (subIndex ?? 0) : 0,
                    ),
                  ),
                  (route) => false,
                );
              },
              onBackToLogin: () {
                AuthService().signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          // Right Main Content
          Expanded(
            child: IgnorePointer(
              ignoring: _isDialogOpen,
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 24, 40, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSearchBar(),
                          const SizedBox(height: 32),
                          if (holiday != null) ...[
                            _buildHolidayBanner(
                              (holiday['name'] ?? '').toString(),
                            ),
                            const SizedBox(height: 24),
                          ],
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left List Section: Worker Attendance Statuses
                                Expanded(
                                  flex: 65,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'worker_attendance'.tr(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textDark,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFFFFFF),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFEEEEEE),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: _buildWorkerAttendanceBody(
                                                  holiday,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              if (holiday == null) _buildPagination(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Right List Section: Today Detailed Attendance Logs
                                Expanded(
                                  flex: 35,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'today_attendance'.tr(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textDark,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFFFFFF),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFEEEEEE),
                                            ),
                                          ),
                                          child: _buildTodayAttendanceBody(holiday),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  void _openAttendanceDialog(
    BuildContext context,
    Map<String, dynamic> data, {
    String? defaultStatus,
    String titleKey = 'mark_attendance',
  }) {
    final isGuest =
        AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    _showMarkAttendanceDialog(
      context,
      data,
      defaultStatus: defaultStatus,
      titleKey: titleKey,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.only(left: 40, right: 40, top: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Color(0xFF000000),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'workforce'.tr(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: textDark,
              fontFamily: 'SF Pro Display',
            ),
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          const UserAvatar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/search icon.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              Color(0xFFBDBDBD),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'search_workers_name_position'.tr(),
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
              ),
            ),
        ],
      ),
    );
  }

  void _showMarkAttendanceDialog(
    BuildContext context,
    Map<String, dynamic> data, {
    String? defaultStatus,
    String titleKey = 'mark_attendance',
  }) {
    final name = data["name"] ?? "";
    final email = data["email"] ?? "";

    // Resolve the worker document (may differ from [data] when this dialog is
    // opened from the Today Summary, where [data] is an attendance record).
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    final normalizedEmail = email.trim().toLowerCase();
    final workerDoc = isGuest
        ? DummyData.workers.firstWhere(
            (w) => (w['email']?.toString() ?? '').toLowerCase() == normalizedEmail,
            orElse: () => <String, dynamic>{},
          )
        : _workers.firstWhere(
            (w) => (w['email']?.toString() ?? '').toLowerCase() == normalizedEmail,
            orElse: () => <String, dynamic>{},
          );
    final balanceDoc = workerDoc.isNotEmpty ? workerDoc : data;

    final todayRecord = _todayAttendance.firstWhere(
      (att) => att['email'] == email,
      orElse: () => <String, dynamic>{},
    );

    const validStatuses = {'Present', 'Absent', 'Leave'};
    // Pre-select the clicked status, otherwise fall back to today's record
    final recordStatus = todayRecord['status'];
    final initialStatus =
        (defaultStatus != null && validStatuses.contains(defaultStatus))
        ? defaultStatus
        : (recordStatus != null && validStatuses.contains(recordStatus))
        ? recordStatus
        : 'Present';
    // Initial values - only from today's attendance record, NOT from worker doc
    final initialReason = todayRecord['desc'] ?? '';

    setState(() => _isDialogOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext dialogContext) {
        String selectedStatus =
            (initialStatus == 'Present' ||
                initialStatus == 'Absent' ||
                initialStatus == 'Leave')
            ? initialStatus
            : 'Present';
        final initialType = (todayRecord['type'] ?? '').toString();
        String selectedLeaveType =
            (initialType.isNotEmpty && initialType != 'Absent')
            ? initialType
            : (selectedStatus == 'Absent' ? 'Without Notice' : 'Sick Leave');

        List<Map<String, String>> reasonOptions() {
          if (selectedStatus == 'Absent') {
            return const [
              {'value': 'Without Notice', 'key': 'absent_without_notice'},
              {'value': 'Sick', 'key': 'absent_sick'},
              {'value': 'Family Emergency', 'key': 'absent_emergency'},
              {'value': 'Other', 'key': 'absent_other'},
            ];
          }
          final options = [
            {'value': 'Sick Leave', 'key': 'sick_leave_type'},
            {'value': 'Casual Leave', 'key': 'casual_leave_type'},
            {'value': 'Annual Leave', 'key': 'annual_leave'},
          ];
          for (final o in options) {
            o['disabled'] =
                (LeaveBalanceHelper.remainingForType(
                          balanceDoc,
                          o['value']!,
                        ) <=
                        0)
                    .toString();
          }
          return options;
        }

        String reasonLabelKey() =>
            selectedStatus == 'Absent' ? 'absent_reason' : 'leave_type';
        final reasonController = TextEditingController(text: initialReason);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return WillPopScope(
              onWillPop: () async => false,
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(0),
                ),
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 440,
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // AppBar (Height: 40)
                        Container(
                          height: 40,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFFFFF),
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFFEEEEEE),
                                width: 1,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Spacer(),
                              Text(
                                titleKey.tr(),
                                style: TextStyle(
                                  color: textDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => Navigator.pop(dialogContext),
                                child: const Icon(
                                  Icons.close,
                                  color: textDark,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Body Section
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedStatus = 'Present';
                                        });
                                      },
                                      child: _buildToggleChip(
                                        'present'.tr(),
                                        'assets/present_worker.svg',
                                        const Color(0xFF00C853),
                                        isSelected: selectedStatus == 'Present',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedStatus = 'Absent';
                                          selectedLeaveType = 'Without Notice';
                                       });
                                      },
                                      child: _buildToggleChip(
                                        'absent'.tr(),
                                        'assets/absent.svg',
                                        const Color(0xFFF44336),
                                        isSelected: selectedStatus == 'Absent',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedStatus = 'Leave';
                                          selectedLeaveType = 'Sick Leave';
                                        });
                                      },
                                      child: _buildToggleChip(
                                        'leave'.tr(),
                                        'assets/leave.svg',
                                        const Color(0xFFFF9800),
                                        isSelected: selectedStatus == 'Leave',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (selectedStatus == 'Leave' ||
                                  selectedStatus == 'Absent') ...[
                                const SizedBox(height: 16),
                                Text(
                                  reasonLabelKey().tr(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      dropdownColor: Colors.white,
                                      value: selectedLeaveType,
                                      items: reasonOptions()
                                          .map(
                                            (o) => DropdownMenuItem(
                                              value: o['value'],
                                              enabled: o['disabled'] != 'true',
                                              child: Text(
                                                (o['key'] ?? '').tr(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontFamily: 'SF Pro Display',
                                                  color: o['disabled'] == 'true'
                                                      ? Colors.grey
                                                      : Colors.black,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setDialogState(() {
                                            selectedLeaveType = value;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                              if (selectedStatus != 'Present') ...[
                                const SizedBox(height: 16),
                                Text(
                                  'reason_required'.tr(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 100,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: TextField(
                                    controller: reasonController,
                                    maxLines: null,
                                    maxLength: 100,
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration.collapsed(
                                      hintText: 'enter_reason_hint'.tr(),
                                      hintStyle: TextStyle(
                                        color: Colors.black.withValues(
                                          alpha: 0.38,
                                        ),
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () {
                                      setState(() => _isDialogOpen = false);
                                      Navigator.pop(dialogContext);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0247C4),
                                      side: const BorderSide(
                                        color: Color(0xFF0247C4),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 14,
                                      ),
                                      minimumSize: const Size(0, 40),
                                      elevation: 0,
                                    ),

                                    child: Text(
                                      'cancel'.tr(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed:
                                        _isSaving ||
                                            (selectedStatus != 'Present' &&
                                                reasonController.text
                                                    .trim()
                                                    .isEmpty)
                                        ? null
                                        : () async {
                                            setState(() => _isSaving = true);
                                            final reason = reasonController.text
                                                .trim();
                                            if (selectedStatus != 'Present' &&
                                                reason.isEmpty) {
                                              if (mounted) {
                                                FlashySnackBar.show(
                                                  context,
                                                  message: 'please_enter_reason'
                                                      .tr(),
                                                  isError: true,
                                                );
                                              }
                                              if (mounted)
                                                setState(
                                                  () => _isSaving = false,
                                                );
                                              return;
                                            }

                                            try {
                                              final isGuest =
                                                  AuthService()
                                                      .currentUser
                                                      ?.isAnonymous ??
                                                  false;
                                              final type =
                                                  (selectedStatus == 'Absent' ||
                                                      selectedStatus == 'Leave')
                                                  ? selectedLeaveType
                                                  : null;
                                              final desc =
                                                  selectedStatus == 'Present'
                                                  ? (reason.isEmpty
                                                        ? null
                                                        : reason)
                                                  : reason;

                                              if (isGuest) {
                                                final wIdx = DummyData.workers
                                                    .indexWhere(
                                                      (w) =>
                                                          w['email'] == email,
                                                    );
                                                if (wIdx != -1) {
                                                  DummyData
                                                          .workers[wIdx]['status'] =
                                                      selectedStatus;
                                                }
                                                final index = DummyData
                                                    .attendance
                                                    .indexWhere(
                                                      (element) =>
                                                          element['email'] ==
                                                          email,
                                                    );
                                                if (index != -1) {
                                                  DummyData
                                                          .attendance[index]['status'] =
                                                      selectedStatus;
                                                  if (type != null) {
                                                    DummyData
                                                            .attendance[index]['type'] =
                                                        type;
                                                  } else {
                                                    DummyData.attendance[index]
                                                        .remove('type');
                                                  }
                                                  if (desc != null &&
                                                      desc.isNotEmpty) {
                                                    DummyData
                                                            .attendance[index]['desc'] =
                                                        desc;
                                                  } else {
                                                    DummyData.attendance[index]
                                                        .remove('desc');
                                                  }
                                                } else {
                                                  final newRecord = {
                                                    'id':
                                                        'dummy_a${DateTime.now().millisecondsSinceEpoch}',
                                                    'name': name,
                                                    'email': email,
                                                    'role':
                                                        data['position'] ??
                                                        data['role'] ??
                                                        '',
                                                    'status': selectedStatus,
                                                    'attendanceType':
                                                        data['attendanceType'] ??
                                                        data['type2'] ??
                                                        'On-Site',
                                                    'workType':
                                                        data['workType'] ??
                                                        data['type1'] ??
                                                        'Full Time',
                                                  };
                                                  if (type != null)
                                                    newRecord['type'] = type;
                                                  if (desc != null &&
                                                      desc.isNotEmpty)
                                                    newRecord['desc'] = desc;
                                                  DummyData.attendance.add(
                                                    newRecord,
                                                  );
                                                  DummyData.saveToPrefs();
                                                }
                                                if (mounted) {
                                                  setState(() {
                                                    _workers =
                                                        List<
                                                          Map<String, dynamic>
                                                        >.from(
                                                          DummyData.workers,
                                                        );
                                                    _todayAttendance =
                                                        List<
                                                          Map<String, dynamic>
                                                        >.from(
                                                          DummyData.attendance,
                                                        );
                                                  });
                                                }
                                              } else {
                                                if (todayRecord.isNotEmpty &&
                                                    todayRecord['id'] != null) {
                                                  await _firestore
                                                      .updateAttendanceRecord(
                                                        todayRecord['id'],
                                                        {
                                                          'name': name,
                                                          'email': email,
                                                          'role':
                                                              data['role'] ??
                                                              data['position'] ??
                                                              '',
                                                          'status':
                                                              selectedStatus,
                                                          'attendanceType':
                                                              data['type2'] ??
                                                              'Remote',
                                                          'workType':
                                                              data['type1'] ??
                                                              'Full Time',
                                                          'type': type,
                                                          'desc': desc,
                                                          'profileImage':
                                                              data['profileImage'],
                                                        },
                                                      );
                                                } else {
                                                  await _firestore
                                                      .addAttendanceRecord({
                                                        'name': name,
                                                        'email': email,
                                                        'role':
                                                            data['role'] ??
                                                            data['position'] ??
                                                            '',
                                                        'status':
                                                            selectedStatus,
                                                        'attendanceType':
                                                            data['type2'] ??
                                                            'Remote',
                                                        'workType':
                                                            data['type1'] ??
                                                            'Full Time',
                                                        'type': type,
                                                        'desc': desc,
                                                        'profileImage':
                                                            data['profileImage'],
                                                      });
                                                }
                                              }

                                              // Adjust the worker's paid leave
                                              // balance per leave type. Decrement
                                              // the chosen type when a NEW leave is
                                              // recorded; restore it when an
                                              // existing Leave is changed to
                                              // Present/Absent.
                                              final previousStatus =
                                                  (todayRecord['status'] ?? '')
                                                      .toString();

                                              Map<String, dynamic>?
                                                  findWorker() {
                                                if (isGuest) {
                                                  final wIdx = DummyData.workers
                                                      .indexWhere(
                                                    (w) =>
                                                        w['email'] == email,
                                                  );
                                                  return wIdx != -1
                                                      ? DummyData.workers[wIdx]
                                                      : null;
                                                }
                                                final worker = _workers.firstWhere(
                                                  (w) =>
                                                      (w['email']
                                                                  ?.toString() ??
                                                              '')
                                                          .toLowerCase() ==
                                                      email.toLowerCase(),
                                                  orElse: () => {},
                                                );
                                                return worker.isNotEmpty
                                                    ? worker
                                                    : null;
                                              }

                                              Future<void> applyLeaveDelta(
                                                String leaveType,
                                                int delta,
                                              ) async {
                                                final availKey =
                                                    LeaveBalanceHelper
                                                        .availKeyForType[
                                                            leaveType];
                                                if (availKey == null) return;
                                                final workerMap = findWorker();
                                                if (workerMap == null) return;
                                                final current =
                                                    LeaveBalanceHelper
                                                        .remainingForType(
                                                  workerMap,
                                                  leaveType,
                                                );
                                                final total =
                                                    LeaveBalanceHelper
                                                        .totalForType(
                                                  workerMap,
                                                  leaveType,
                                                );
                                                final newVal = (current + delta)
                                                    .clamp(0, total);
                                                if (isGuest) {
                                                  final wIdx = DummyData.workers
                                                      .indexWhere(
                                                    (w) =>
                                                        w['email'] == email,
                                                  );
                                                  if (wIdx != -1) {
                                                    DummyData.workers[wIdx]
                                                            [availKey] =
                                                        newVal;
                                                    if (mounted) {
                                                      setState(() {
                                                        _workers = List<
                                                          Map<String, dynamic>
                                                        >.from(
                                                          DummyData.workers,
                                                        );
                                                      });
                                                    }
                                                  }
                                                } else {
                                                  final id = workerMap['id'];
                                                  if (id != null) {
                                                    await _firestore
                                                        .updateWorkerLeaves(
                                                      id,
                                                      {availKey: newVal},
                                                    );
                                                  }
                                                }
                                              }

                                              if (selectedStatus == 'Leave' &&
                                                  previousStatus != 'Leave') {
                                                await applyLeaveDelta(
                                                  selectedLeaveType,
                                                  -1,
                                                );
                                              } else if (previousStatus ==
                                                      'Leave' &&
                                                  selectedStatus != 'Leave') {
                                                await applyLeaveDelta(
                                                  (todayRecord['type'] ?? '')
                                                      .toString(),
                                                  1,
                                                );
                                              }

                                              if (!context.mounted) {
                                                if (mounted)
                                                  setState(
                                                    () => _isSaving = false,
                                                  );
                                                return;
                                              }
                                              FlashySnackBar.show(
                                                context,
                                                message:
                                                    'attendance_updated_success'
                                                        .tr(
                                                          namedArgs: {
                                                            'name': name,
                                                          },
                                                        ),
                                              );
                                            } catch (e) {
                                              if (!context.mounted) {
                                                if (mounted)
                                                  setState(
                                                    () => _isSaving = false,
                                                  );
                                                return;
                                              }
                                              FlashySnackBar.show(
                                                context,
                                                message:
                                                    'attendance_update_failed'
                                                        .tr(
                                                          namedArgs: {
                                                            'error': e
                                                                .toString(),
                                                          },
                                                        ),
                                                isError: true,
                                              );
                                            }
                                            if (mounted) Navigator.pop(context);
                                            if (mounted)
                                              setState(() => _isSaving = false);
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F52BA),
                                      disabledBackgroundColor: const Color(
                                        0xFFB0BEC5,
                                      ),
                                      disabledForegroundColor: const Color(
                                        0xFFE0E0E0,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 14,
                                      ),
                                      minimumSize: const Size(0, 40),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      'save'.tr(),
                                      style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  Widget _buildPagination() {
    final filtered = _filteredWorkers;
    final totalPages = (filtered.isEmpty)
        ? 1
        : (filtered.length / _itemsPerPage).ceil();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
          behavior: HitTestBehavior.opaque,
          child: Icon(
            Icons.chevron_left,
            size: 24,
            color: _currentPage > 1 ? textDark : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: primaryBlue,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$_currentPage',
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _currentPage < totalPages
              ? () => setState(() => _currentPage++)
              : null,
          behavior: HitTestBehavior.opaque,
          child: Icon(
            Icons.chevron_right,
            size: 24,
            color: _currentPage < totalPages ? textDark : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _buildHolidayBanner(String name) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B51C1), Color(0xFF1E5EE0)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/holidays_icon.svg',
            width: 32,
            height: 32,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'today_is_holiday'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                if (name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayNotice(String name) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/holidays_icon.svg',
            width: 56,
            height: 56,
            colorFilter: const ColorFilter.mode(
              Color(0xFF0B51C1),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'today_is_holiday'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textDark,
              fontFamily: 'SF Pro Display',
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                color: textMuted,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'holiday_attendance_disabled'.tr(),
            style: const TextStyle(
              fontSize: 13,
              color: textMuted,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerAttendanceBody(Map<String, dynamic>? holiday) {
    if (holiday != null) {
      return _buildHolidayNotice((holiday['name'] ?? '').toString());
    }
    if (_filteredWorkers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/placeholdemptystate.png',
              width: 120,
              height: 100,
              color: const Color(0xFFCBCBCB),
            ),
            const SizedBox(height: 16),
            Text(
              'no_workers_found_title'.tr(),
              style: const TextStyle(
                color: Color(0xFF0247C1),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final paginatedList = _filteredWorkers
        .skip(startIndex)
        .take(_itemsPerPage)
        .toList();
    return SingleChildScrollView(
      child: Column(
        children: paginatedList.asMap().entries.map(
          (entry) => WorkerListItem(
            data: entry.value,
            index: entry.key,
            currentStatus: _getWorkerStatus(entry.value),
            onMarkAttendance: (status) => _openAttendanceDialog(
              context,
              entry.value,
              defaultStatus: status,
            ),
          ),
        ).toList(),
      ),
    );
  }

  Widget _buildTodayAttendanceBody(Map<String, dynamic>? holiday) {
    if (holiday != null) {
      return _buildHolidayNotice((holiday['name'] ?? '').toString());
    }
    if (_todayAttendance.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/placeholdemptystate.png',
              width: 120,
              height: 100,
              color: const Color(0xFFCBCBCB),
            ),
            const SizedBox(height: 16),
            Text(
              'no_attendance_records'.tr(),
              style: const TextStyle(
                color: Color(0xFF0247C1),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: _todayAttendance.asMap().entries.map(
          (entry) => TodayAttendanceItem(
            data: entry.value,
            index: entry.key,
            onEdit: () => _openAttendanceDialog(
              context,
              entry.value,
              defaultStatus: (entry.value['status'] ?? 'Present').toString(),
              titleKey: 'edit_attendance',
            ),
          ),
        ).toList(),
      ),
    );
  }

  Widget _buildToggleChip(
    String label,
    String asset,
    Color iconColor, {
    bool isSelected = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF0F52BA) : Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? const Color(0xFF0F52BA) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          asset.endsWith('.svg')
              ? SvgPicture.asset(asset, height: 20, width: 20)
              : Image.asset(asset, height: 20, width: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Color(0xFFFFFFFF) : Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class WorkerListItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final String currentStatus;
  final ValueChanged<String> onMarkAttendance;

  const WorkerListItem({
    super.key,
    required this.data,
    required this.index,
    this.currentStatus = '',
    required this.onMarkAttendance,
  });

  @override
  Widget build(BuildContext context) {
    final leaveExhausted = LeaveBalanceHelper.allLeavesExhausted(data);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage: _getProfileImage(
              data['profileImage'] is String
                  ? data['profileImage'] as String
                  : null,
              data['email']?.toString(),
              index,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data["name"] ?? '').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  (data["email"] ?? '').toString(),
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          // Show attendance action buttons when no attendance has been marked yet,
          // otherwise show "Attendance marked" label
          if (currentStatus.isEmpty) ...[
            const SizedBox(width: 12),
            _AttendanceActionButton(
              labelKey: 'present',
              status: 'Present',
              color: const Color(0xFF00C853),
              onTap: onMarkAttendance,
            ),
            const SizedBox(width: 8),
            _AttendanceActionButton(
              labelKey: 'absent',
              status: 'Absent',
              color: const Color(0xFFF44336),
              onTap: onMarkAttendance,
            ),
            const SizedBox(width: 8),
            _AttendanceActionButton(
              labelKey: 'leave',
              status: 'Leave',
              color: const Color(0xFFFF9800),
              enabled: !leaveExhausted,
              onTap: onMarkAttendance,
              onDisabledTap: () {
                FlashySnackBar.show(
                  context,
                  message: 'paid_leave_exhausted'.tr(),
                  isError: true,
                );
              },
            ),
          ] else ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E5EA),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Attendance Marked',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceActionButton extends StatelessWidget {
  final String labelKey;
  final String status;
  final Color color;
  final bool enabled;
  final bool selected;
  final ValueChanged<String> onTap;
  final VoidCallback? onDisabledTap;

  const _AttendanceActionButton({
    required this.labelKey,
    required this.status,
    required this.color,
    this.enabled = true,
    this.selected = false,
    required this.onTap,
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled;
    return GestureDetector(
      onTap: isEnabled
          ? () => onTap(status)
          : onDisabledTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled ? color : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border.all(color: Color(0xFFFFFFFF), width: 2)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.check,
                  color: Color(0xFFFFFFFF),
                  size: 14,
                ),
              ),
            Text(
              labelKey.tr(),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TodayAttendanceItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback? onEdit;

  const TodayAttendanceItem({
    super.key,
    required this.data,
    required this.index,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: _getProfileImage(
                  data['profileImage'] is String
                      ? data['profileImage'] as String
                      : null,
                  data['email']?.toString(),
                  index,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  (data["name"] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(status: (data["status"] ?? '').toString()),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onEdit,
                child: SvgPicture.asset(
                  'assets/edit_icon.svg',
                  height: 20,
                  width: 20,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF000000),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ],
          ),
          if (data["type"] != null) ...[
            const SizedBox(height: 12),
            Text(
              (data["status"] == 'Leave' ? 'leave_type_display' : 'absent_type')
                  .tr(namedArgs: {'type': data["type"].toString()}),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textDark,
                fontFamily: 'SF Pro Display',
              ),
            ),
            if (data["desc"] != null) ...[
              const SizedBox(height: 6),
              Text(
                (data["desc"] ?? '').toString(),
                style: const TextStyle(
                  fontSize: 12,
                  color: textMuted,
                  height: 1.3,
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 2,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor = pillGray;
    Color textColor = Color(0xFFFFFFFF);
    final displayStatus = (status.isEmpty || status == "*****")
        ? "*****"
        : status;

    if (displayStatus == "*****") {
      bgColor = pillGray;
      textColor = textDark;
    } else if (displayStatus == "Present") {
      bgColor = greenPresent;
    } else if (displayStatus == "Absent") {
      bgColor = redAbsent;
    } else if (displayStatus == "Leave") {
      bgColor = orangeLeave;
    } else {
      bgColor = pillGray;
      textColor = textDark;
    }

    return Container(
      width: 80,
      alignment: Alignment.center,

      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        displayStatus,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          fontFamily: 'SF Pro Display',
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

ImageProvider _getProfileImage(String? url, String? email, int index) {
  return getProfileImage(url, email, index);
}
