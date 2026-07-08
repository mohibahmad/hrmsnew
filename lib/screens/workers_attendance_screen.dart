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
import '../utils/logout_dialog.dart';
import '../utils/snackbar_utils.dart';
import '../utils/image_utils.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';

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
  const WorkersAttendanceScreen({super.key, this.onNotificationTap});

  @override
  State<WorkersAttendanceScreen> createState() =>
      _WorkersAttendanceScreenState();
}

class _WorkersAttendanceScreenState extends State<WorkersAttendanceScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  int _currentPage = 1;
  static const int _itemsPerPage = 10;
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _todayAttendance = [];
  bool _isLoading = true;
  bool _isDialogOpen = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isPremium = false;
  final FirestoreService _firestore = FirestoreService();
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;

  @override
  void dispose() {
    _workersSub?.cancel();
    _attendanceSub?.cancel();
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
        _todayAttendance = List<Map<String, dynamic>>.from(
          DummyData.attendance,
        );
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
            _isLoading = false;
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
            _todayAttendance = sortedList;
            _isLoading = false;
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
    final filteredWorkers = _filteredWorkers;

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
          // Left Sidebar (Standard SidebarWidget)
          IgnorePointer(
            ignoring: _isDialogOpen,
            child: SidebarWidget(
              key: ValueKey('sidebar_${context.locale.languageCode}'),
              selectedIndex: 2,
              selectedSubIndex: 0,
              isGuest: AuthService().currentUser?.isAnonymous ?? false,
              isPremium: _isPremium,
              onItemSelected: (index, {subIndex}) {
                Navigator.of(context, rootNavigator: true).pop();
              },
              onBackToLogin: () {
                AuthService().signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
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
                                                child: filteredWorkers.isEmpty
                                                    ? Center(
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Image.asset(
                                                              'assets/placeholdemptystate.png',
                                                              width: 120,
                                                              height: 100,
                                                              color:
                                                                  const Color(
                                                                    0xFFCBCBCB,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              height: 16,
                                                            ),
                                                            Text(
                                                              'no_workers_found_title'
                                                                  .tr(),
                                                              style: const TextStyle(
                                                                color: Color(
                                                                  0xFF0247C4,
                                                                ),
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontFamily:
                                                                    'SF Pro Display',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    : SingleChildScrollView(
                                                        child: Column(
                                                          children: () {
                                                            final startIndex =
                                                                (_currentPage -
                                                                    1) *
                                                                _itemsPerPage;
                                                            final paginatedList =
                                                                filteredWorkers
                                                                    .skip(
                                                                      startIndex,
                                                                    )
                                                                    .take(
                                                                      _itemsPerPage,
                                                                    )
                                                                    .toList();
                                                            return paginatedList
                                                                .asMap()
                                                                .entries
                                                                .map(
                                                                  (
                                                                    entry,
                                                                  ) => WorkerListItem(
                                                                    data: entry
                                                                        .value,
                                                                    index: entry
                                                                        .key,
                                                                    onMarkAttendance: () =>
                                                                        _showMarkAttendanceDialog(
                                                                          context,
                                                                          entry
                                                                              .value,
                                                                        ),
                                                                  ),
                                                                )
                                                                .toList();
                                                          }(),
                                                        ),
                                                      ),
                                              ),
                                              const SizedBox(height: 8),
                                              _buildPagination(),
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
                                          child: _todayAttendance.isEmpty
                                              ? Center(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Image.asset(
                                                        'assets/placeholdemptystate.png',
                                                        width: 120,
                                                        height: 100,
                                                        color: const Color(
                                                          0xFFCBCBCB,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      Text(
                                                        'no_attendance_records'
                                                            .tr(),
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF0247C4,
                                                          ),
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : SingleChildScrollView(
                                                  child: Column(
                                                    children: _todayAttendance
                                                        .asMap()
                                                        .entries
                                                        .map(
                                                          (entry) =>
                                                              TodayAttendanceItem(
                                                                data:
                                                                    entry.value,
                                                                index:
                                                                    entry.key,
                                                              ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ),
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

  Widget _buildHeader(BuildContext context) {
    final user = AuthService().currentUser;
    final name = user?.displayName ?? 'User';

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
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.only(top: 2.0),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Color(0xFF000000),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
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
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                showLogoutDialog(context);
              }
            },
            offset: const Offset(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            color: Color(0xFFFFFFFF),
            elevation: 8,
            tooltip: '',
            child: const UserAvatar(),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                enabled: false,
                padding: EdgeInsets.zero,
                height: 0,
                child: SizedBox.shrink(),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'logout'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    Map<String, dynamic> data,
  ) {
    final name = data["name"] ?? "";
    final email = data["email"] ?? "";

    final todayRecord = _todayAttendance.firstWhere(
      (att) => att['email'] == email,
      orElse: () => <String, dynamic>{},
    );

    // Initial values
    final initialStatus = todayRecord['status'] ?? data['status'] ?? 'Present';
    final initialReason = todayRecord['desc'] ?? '';

    setState(() => _isDialogOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        String selectedStatus =
            (initialStatus == 'Present' ||
                initialStatus == 'Absent' ||
                initialStatus == 'Leave')
            ? initialStatus
            : 'Present';
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
                        // AppBar (Height: 40, Color: #004FDE)
                        Container(
                          height: 40,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Color(0xFF004FDE),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Spacer(),
                              Text(
                                'mark_attendance'.tr(),
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(
                                  Icons.close,
                                  color: Color(0xFFFFFFFF),
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Profile Section (Color: #0247C4)
                        Container(
                          color: const Color(0xFF0247C4),
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Profile Image: 140x140, circular with 2px border
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Color(0xFFFFFFFF),
                                    width: 2,
                                  ),
                                  image: DecorationImage(
                                    image: _getProfileImage(
                                      data['profileImage'] is String
                                          ? data['profileImage'] as String
                                          : null,
                                      data['email']?.toString(),
                                      0,
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 40),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 32,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'SF Pro Display',
                                          height: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.email,
                                            color: Color(0xFFFFFFFF),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              email,
                                              style: const TextStyle(
                                                color: Color(0xFFFFFFFF),
                                                fontSize: 14,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 2),
                                            child: Icon(
                                              Icons.phone,
                                              color: Color(0xFFFFFFFF),
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              (() {
                                                final phone =
                                                    (data['phone'] ??
                                                            data['contact'] ??
                                                            '')
                                                        .toString();
                                                return phone.isNotEmpty
                                                    ? phone
                                                    : 'na'.tr();
                                              })(),
                                              style: const TextStyle(
                                                color: Color(0xFFFFFFFF),
                                                fontSize: 14,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                              softWrap: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
                                        'assets/present.svg',
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
                              const SizedBox(height: 16),
                              Text(
                                selectedStatus == 'Present'
                                    ? 'reason_optional'.tr()
                                    : 'reason_required'.tr(),
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
                                  onChanged: (_) => setDialogState(() {}),
                                  decoration: InputDecoration.collapsed(
                                    hintText: 'enter_reason_hint'.tr(),
                                    hintStyle: TextStyle(
                                      color: Colors.black.withValues(alpha: 0.38),
                                      fontSize: 13,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 14,
                                      ),
                                      minimumSize: const Size(0, 40),
                                    ),
                                    child: Text(
                                      'cancel'.tr(),
                                      style: TextStyle(
                                        color: Colors.black,
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
                                                  selectedStatus == 'Absent'
                                                  ? (data['type'] ?? 'Absent')
                                                  : (selectedStatus == 'Leave'
                                                        ? (data['type'] ??
                                                              'Sick Leave')
                                                        : null);
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
                                                final workerId = data['id'];
                                                if (workerId != null) {
                                                  final Map<String, dynamic>
                                                  updatedWorker =
                                                      Map<String, dynamic>.from(
                                                        data,
                                                      );
                                                  updatedWorker['status'] =
                                                      selectedStatus;
                                                  updatedWorker.remove('id');
                                                  await _firestore.updateWorker(
                                                    workerId,
                                                    updatedWorker,
                                                  );
                                                }

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

  Widget _buildToggleChip(
    String label,
    String svgAsset,
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
          SvgPicture.asset(svgAsset, height: 18, width: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Color(0xFFFFFFFF) : Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }
}

class WorkerListItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback onMarkAttendance;

  const WorkerListItem({
    super.key,
    required this.data,
    required this.index,
    required this.onMarkAttendance,
  });

  @override
  Widget build(BuildContext context) {
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
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
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
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(right: 24.0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: pillGray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  (data["role"] ?? data["position"] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: textDark,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: StatusPill(status: (data["status"] ?? '').toString()),
            ),
          ),
          const SizedBox(width: 64),
          GestureDetector(
            onTap: onMarkAttendance,
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
    );
  }
}

class TodayAttendanceItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;

  const TodayAttendanceItem({
    super.key,
    required this.data,
    required this.index,
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
            ],
          ),
          if (data["type"] != null) ...[
            const SizedBox(height: 12),
            Text(
              'absent_type'.tr(namedArgs: {'type': data["type"].toString()}),
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
