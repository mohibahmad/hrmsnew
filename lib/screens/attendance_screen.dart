import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/attendance_service.dart';
import '../services/time_off_service.dart';
import '../widgets/notification_bell.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import 'workers_attendance_screen.dart';
import '../utils/image_utils.dart';
import '../utils/date_utils.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';
import '../utils/guest_restriction.dart';
import 'package:provider/provider.dart';

const Color primaryBlue = Color(0xFF0B51C1);
const Color lightBlueBg = Color(0xFFE8F0FE);
const Color bgGray = Color(0xFFF8FAFC);
const Color textDark = Color(0xFF000000);
const Color textMuted = Color(0xFF64748B);

const Color greenPresent = Color(0xFF00FF2A);
const Color greenPresentBg = Color(0x3300FF2A);
const Color redAbsent = Color(0xFFFF0004);
const Color redAbsentBg = Color(0x33FF0004);
const Color orangeLeave = Color(0xFFFF7B00);
const Color orangeLeaveBg = Color(0x33FF7B00);

class AttendanceRecord {
  final String name;
  final String email;
  final String role;
  final String status;
  final String attendanceType;
  final String workType;
  final String? profileImage;
  final String? phone;

  AttendanceRecord({
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.attendanceType = 'Remote',
    this.workType = 'Full Time',
    this.profileImage,
    this.phone,
  });

  String get localizedWorkType {
    switch (workType) {
      case 'Full Time':
        return 'full_time'.tr();
      case 'Part Time':
        return 'part_time'.tr();
      case 'Contract':
        return 'contract'.tr();
      default:
        return workType;
    }
  }

  String get localizedAttendanceType {
    switch (attendanceType) {
      case 'On-Site':
        return 'on_site'.tr();
      case 'Remote':
        return 'remote'.tr();
      case 'Hybrid':
        return 'hybrid'.tr();
      default:
        return attendanceType;
    }
  }
}

class AttendanceScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onWorkersAttendanceTap;

  const AttendanceScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
    this.onWorkersAttendanceTap,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late AuthService _authService;
  late FirestoreService _firestore;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTab = 'All';
  String _selectedTimeframe = 'Today';
  List<Map<String, dynamic>> _attendanceDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawAttendanceDocs = [];
  List<Map<String, dynamic>> _timeOffRecords = [];
  bool _isLoading = true;
  bool _workersLoaded = false;
  bool _attendanceLoaded = false;

  int _presentCount = 0;
  int _absentCount = 0;
  int _leaveCount = 0;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _timeOffSub;
  Timer? _searchDebounce;
  List<Map<String, dynamic>>? _cachedFiltered;
  String _filterCacheKey = '';

  @override
  void dispose() {
    _attendanceSub?.cancel();
    _workersSub?.cancel();
    _timeOffSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _combineAttendance() {
    _cachedFiltered = null;
    _filterCacheKey = '';

    _attendanceDocs =
        AttendanceService.combineAttendance(
          workersList: _workersList,
          rawAttendanceDocs: _rawAttendanceDocs,
        ).map((record) {
          final isOnLeave = TimeOffService.isWorkerOnLeave(
            record,
            _timeOffRecords,
          );
          if (isOnLeave) {
            return {
              ...record,
              'status': 'Leave',
            };
          }
          return record;
        }).toList();

    if (_workersLoaded && _attendanceLoaded) {
      _isLoading = false;
    }

    int present = 0;
    int absent = 0;
    int leave = 0;

    for (final record in _attendanceDocs) {
      if (!_matchesPeriod(record)) continue;
      final status = record['status'];
      if (status == 'Present') {
        present++;
      } else if (status == 'Absent') {
        absent++;
      } else if (status == 'Leave') {
        leave++;
      }
    }

    _presentCount = present;
    _absentCount = absent;
    _leaveCount = leave;
  }

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    _attendanceDocs = [];
    _workersList = [];
    _rawAttendanceDocs = [];
    _isLoading = true;
    _workersLoaded = false;
    _attendanceLoaded = false;
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _workersList = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              _workersLoaded = true;
              _combineAttendance();
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _workersLoaded = true;
              _isLoading = false;
            });
          }
        },
      );
      _attendanceSub = _firestore.attendanceStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _rawAttendanceDocs = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              _attendanceLoaded = true;
              _combineAttendance();
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _attendanceLoaded = true;
              _isLoading = false;
            });
          }
        },
      );
      _timeOffSub = _firestore.timeoffStream.listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _timeOffRecords = snapshot.docs
              .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
              .toList();
          _combineAttendance();
        });
      }, onError: (_) {});
    } else {
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawAttendanceDocs = List<Map<String, dynamic>>.from(
        DummyData.attendance,
      );
      _timeOffRecords = List<Map<String, dynamic>>.from(DummyData.timeoff);
      _workersLoaded = true;
      _attendanceLoaded = true;
      _combineAttendance();
    }
  }

  String _getTimeframeTitle() {
    switch (_selectedTimeframe) {
      case 'Today':
        return 'today_attendance'.tr();
      case 'Week':
        return 'weekly_attendance'.tr();
      case 'Month':
        return 'monthly_attendance'.tr();
      case '6 Month':
        return 'six_month_attendance'.tr();
      case 'Yearly':
        return 'yearly_attendance'.tr();
      default:
        return 'today_attendance'.tr();
    }
  }

  bool _matchesPeriod(Map<String, dynamic> doc) {
    final createdAt = doc['createdAt'];
    if (createdAt == null) return true;
    return AppDateUtils.isTimestampWithinPeriod(createdAt, _selectedTimeframe);
  }

  List<Map<String, dynamic>> get _filteredRecords {
    final key = '${_attendanceDocs.length}_$_searchQuery$_selectedTab$_selectedTimeframe';
    if (_cachedFiltered != null && _filterCacheKey == key) {
      return _cachedFiltered!;
    }
    _filterCacheKey = key;
    final query = _searchQuery.toLowerCase();
    _cachedFiltered = _attendanceDocs.where((doc) {
      if (!_matchesPeriod(doc)) return false;
      if (query.isNotEmpty) {
        final name = (doc['name'] ?? '').toString().toLowerCase();
        final role = (doc['role'] ?? '').toString().toLowerCase();
        if (!name.contains(query) && !role.contains(query)) return false;
      }
      final status = (doc['status'] ?? '').toString();
      if (_selectedTab == 'All') return true;
      if (_selectedTab == 'Present') return status == 'Present';
      if (_selectedTab == 'Absent') return status == 'Absent';
      if (_selectedTab == 'Leaves') return status == 'Leave';
      return false;
    }).toList();
    return _cachedFiltered!;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: bgGray,
      body: Column(
        children: [

          _buildHeader(context),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 40.0,
                vertical: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchAndActionRow(),
                  const SizedBox(height: 24),
                  _buildSummaryCardsRow(),
                  const SizedBox(height: 24),
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getTimeframeTitle(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textDark,
                                fontFamily: 'SF Pro Display',
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 20),
                            if (_isLoading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 80),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (filtered.isEmpty)
                              _buildEmptyState()
                            else
                              _buildAttendanceTable(filtered),
                          ],
                        ),
                      ),


                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'workforce'.tr(),
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
            ],
          ),
          const Spacer(),

          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onProfileTap,
              child: const UserAvatar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndActionRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
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
                      _searchQuery = val;
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                        if (mounted) setState(() {});
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'search_by_workers_name'.tr(),
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
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              final isGuest = _authService.currentUser?.isAnonymous ?? false;
              if (isGuest) {
                showGuestRestrictionDialog(context);
                return;
              }
              if (widget.onWorkersAttendanceTap != null) {
                widget.onWorkersAttendanceTap!();
              } else {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => WorkersAttendanceScreen(
                      onNotificationTap: widget.onNotificationTap,
                      onProfileTap: widget.onProfileTap,
                    ),
                    transitionsBuilder: (_, __, ___, child) => child,
                    transitionDuration: Duration.zero,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Text(
              'workers_attendance'.tr(),
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCardsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            title: 'total_workers'.tr(),
            count: "${_workersList.length}",
            iconAsset: 'assets/total_workers.svg',
            countColor: const Color(0xFF0247C4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'Present'.tr(),
            count: "$_presentCount",
            iconAsset: 'assets/present_worker.svg',
            countColor: const Color(0xFF00FF2A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'Absent'.tr(),
            count: "$_absentCount",
            iconAsset: 'assets/absent.svg',
            countColor: const Color(0xFFFF0004),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'On leave'.tr(),
            count: "$_leaveCount",
            iconAsset: 'assets/leave.svg',
            countColor: const Color(0xFFFF7B00),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String count,
    required String iconAsset,
    required Color countColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 12),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: countColor,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          iconAsset.endsWith('.svg')
              ? SvgPicture.asset(iconAsset, height: 28, width: 28)
              : Image.asset(iconAsset, height: 28, width: 28),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTab('All', 'all_tab'.tr()),
            _buildTab('Present', 'present_tab'.tr()),
            _buildTab('Absent', 'absent_tab'.tr()),
            _buildTab('Leaves', 'leaves_tab'.tr()),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String filterKey, String displayLabel) {
    final bool isActive = _selectedTab == filterKey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = filterKey;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isActive ? 8 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isActive ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            displayLabel,
            style: TextStyle(
              color: isActive ? Color(0xFFFFFFFF) : textDark,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearchEmpty = _searchQuery.isNotEmpty;
    double dynamicHeight = MediaQuery.of(context).size.height - 520;
    if (dynamicHeight < 300) dynamicHeight = 300;
    return Container(
      width: double.infinity,
      height: dynamicHeight,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/placeholdemptystate.png',
              width: 120,
              height: 100,
              color: const Color(0xFFCBCBCB),
            ),
            const SizedBox(height: 16),
            Text(
              isSearchEmpty
                  ? 'no_search_results'.tr()
                  : 'no_attendance_records'.tr(),
              style: TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  void _showAttendancePreview(BuildContext context, Map<String, dynamic> doc) {
    final workerRecords = AttendanceService.recordsForWorker(
      worker: doc,
      attendanceRecords: _rawAttendanceDocs,
    );

    int totalWorkingDays = workerRecords.length;
    int absents = workerRecords.where((d) => d['status'] == 'Absent').length;
    int leaves = workerRecords.where((d) => d['status'] == 'Leave').length;
    int presents = workerRecords.where((d) => d['status'] == 'Present').length;
    double percentage = totalWorkingDays > 0
        ? (presents / totalWorkingDays) * 100
        : 0.0;

    final record = AttendanceRecord(
      name: (doc['name'] ?? '').toString(),
      email: (doc['email'] ?? '').toString(),
      role: (doc['role'] ?? '').toString(),
      status: (doc['status'] ?? '').toString(),
      attendanceType: (doc['attendanceType'] ?? 'Remote').toString(),
      workType: (doc['workType'] ?? 'Full Time').toString(),
      profileImage: doc['profileImage']?.toString(),
      phone: doc['phone']?.toString(),
    );

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: WorkerAttendancePreviewCard(
          record: record,
          totalWorkingDays: totalWorkingDays,
          presents: presents,
          absents: absents,
          leaves: leaves,
          percentage: percentage,
          workerRecords: workerRecords,
        ),
      ),
    );
  }

  Widget _buildAttendanceTable(List<Map<String, dynamic>> records) {
    final double tableHeight = (MediaQuery.of(context).size.height - 465).clamp(
      480.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [

          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('worker_name_header'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('status_header'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('work_type'.tr()),
                  ),
                ),
                Expanded(flex: 2, child: _tableHeader('position'.tr())),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: records.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = records[index];
                final name = (doc['name'] ?? '').toString();
                final email = (doc['email'] ?? '').toString();
                final role = (doc['role'] ?? '').toString();
                final status = (doc['status'] ?? '').toString();
                final workType = (doc['workType'] ?? 'Full Time').toString();

                final localizeWorkType = LocalizationHelper.localizeWorkType;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FA),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24.0),
                          child: Row(
                            children: [
                              WorkerAvatar(
                                imageUrl: doc['profileImage']?.toString(),
                                name: name,
                                size: 40,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: textDark,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      email,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24.0),
                          child: Text(
                            status.isEmpty ? '-' : status.toLowerCase().tr(),
                            style: TextStyle(
                              color: status == 'Present'
                                  ? greenPresent
                                  : (status == 'Absent'
                                        ? redAbsent
                                        : (status.isEmpty
                                              ? Colors.grey
                                              : orangeLeave)),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24.0),
                          child: Text(
                            localizeWorkType(workType),
                            style: const TextStyle(
                              fontSize: 15,
                              color: textDark,
                              fontFamily: 'SF Pro Display',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          role,
                          style: const TextStyle(
                            fontSize: 15,
                            color: textDark,
                            fontFamily: 'SF Pro Display',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _showAttendancePreview(context, doc),
                            child: const Icon(
                              Icons.visibility,
                              color: Colors.black,
                              size: 24,
                            ),
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
      ),
    );
  }

  Widget _tableHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
    );
  }
}

class WorkerAttendancePreviewCard extends StatefulWidget {
  final AttendanceRecord record;
  final int totalWorkingDays;
  final int presents;
  final int absents;
  final int leaves;
  final double percentage;
  final List<Map<String, dynamic>> workerRecords;

  const WorkerAttendancePreviewCard({
    super.key,
    required this.record,
    required this.totalWorkingDays,
    required this.presents,
    required this.absents,
    required this.leaves,
    required this.percentage,
    required this.workerRecords,
  });

  @override
  State<WorkerAttendancePreviewCard> createState() =>
      _WorkerAttendancePreviewCardState();
}

class _WorkerAttendancePreviewCardState
    extends State<WorkerAttendancePreviewCard> {
  String _selectedPeriod = 'All';

  List<Map<String, dynamic>> get _filteredRecords {
    if (_selectedPeriod == 'All') return widget.workerRecords;
    return widget.workerRecords.where((att) {
      final createdAt = att['createdAt'];
      if (createdAt == null) return true;
      return AppDateUtils.isTimestampWithinPeriod(createdAt, _selectedPeriod);
    }).toList();
  }

  int get _filteredTotal => _filteredRecords.length;
  int get _filteredPresents =>
      _filteredRecords.where((d) => d['status'] == 'Present').length;
  int get _filteredAbsents =>
      _filteredRecords.where((d) => d['status'] == 'Absent').length;
  int get _filteredLeaves =>
      _filteredRecords.where((d) => d['status'] == 'Leave').length;
  double get _filteredPercentage =>
      _filteredTotal > 0 ? (_filteredPresents / _filteredTotal) * 100 : 0.0;

  static const Color primaryBlue = Color(0xFF0A51D0);

  static const Color lightGreenBg = Color(0xFFE4F9E8);
  static const Color darkGreen = Color(0xFF00C853);

  static const Color lightRedBg = Color(0xFFFCE9EA);
  static const Color darkRed = Color(0xFFFF1717);

  static const Color lightOrangeBg = Color(0xFFFEF0E2);
  static const Color darkOrange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 500,
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
            _buildBlueHeader(context),
            _buildMiddleSummary(),
            _buildBottomDetails(),
          ],
        ),
      ),
    );
  }

  Widget _buildBlueHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF004FDE),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFFFFFFFF),
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                'worker_attendance_preview'.tr(),
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: SvgPicture.asset(
                      'assets/share1.svg',
                      height: 18,
                      width: 18,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFFFFFFF),
                        BlendMode.srcIn,
                      ),
                    ),
                    onPressed: () => _exportCsv(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: const Color(0xFFFFFFFF),
          padding: const EdgeInsets.fromLTRB(32, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              WorkerAvatar(
                imageUrl: widget.record.profileImage,
                name: widget.record.name,
                size: 60,
                border: Border.all(color: const Color(0xFF0A51D0), width: 2),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.record.name,
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SvgPicture.asset(
                          'assets/email.svg',
                          height: 12,
                          width: 12,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF666666),
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.record.email,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Align(
                  alignment: Alignment.center,
                  child: CustomTimeframeDropdown(
                    selectedPeriod: _selectedPeriod,
                    onChanged: (value) {
                      setState(() {
                        _selectedPeriod = value;
                      });
                    },
                    options: const ['All', 'Monthly', '3 Month', 'Yearly'],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiddleSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'total_presents'.tr(),
              value: '$_filteredPresents',
              bgColor: lightGreenBg,
              iconColor: darkGreen,
              iconBuilder: (color) => _buildPresentIcon(color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'total_absent'.tr(),
              value: '$_filteredAbsents',
              bgColor: lightRedBg,
              iconColor: darkRed,
              iconBuilder: (color) => _buildAbsentIcon(color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'total_leaves'.tr(),
              value: '$_filteredLeaves',
              bgColor: lightOrangeBg,
              iconColor: darkOrange,
              iconBuilder: (color) => _buildLeaveIcon(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color bgColor,
    required Color iconColor,
    required Widget Function(Color) iconBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Color(0xFF000000).withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconBuilder(iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                Text(
                  'days_label'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentIcon(Color color) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(Icons.person, color: color, size: 28),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(1),
              child: Icon(Icons.check_circle, color: color, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsentIcon(Color color) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(Icons.person, color: color, size: 28),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(1),
              child: Icon(Icons.cancel, color: color, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveIcon(Color color) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(Icons.person, color: color, size: 28),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(1),
              child: Icon(Icons.work, color: color, size: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDetails() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: _buildDetailCard(
                title: 'attendance_label'.tr(),
                rows: [
                  _buildDetailRow(
                    'total_working_days'.tr(),
                    '$_filteredTotal ${'days_unit'.tr()}',
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'total_presents'.tr(),
                    '$_filteredPresents ${'days_unit'.tr()}',
                    darkGreen,
                  ),
                  _buildDetailRow(
                    'total_absents'.tr(),
                    '$_filteredAbsents ${'days_unit'.tr()}',
                    darkRed,
                  ),
                  _buildDetailRow(
                    'total_leaves'.tr(),
                    '$_filteredLeaves ${'days_unit'.tr()}',
                    darkOrange,
                  ),
                  _buildDetailRow(
                    'attendance_percentage'.tr(),
                    '${_filteredPercentage.toStringAsFixed(1)}%',
                    primaryBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 205,
              child: _buildDetailCard(
                title: 'worker_information'.tr(),
                rows: [
                  _buildDetailRow(
                    'position'.tr(),
                    widget.record.role,
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'work_type'.tr(),
                    widget.record.localizedWorkType,
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'attendance_type'.tr(),
                    widget.record.localizedAttendanceType,
                    Color(0xFF000000),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({required String title, required List<Widget> rows}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: primaryBlue,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final List<List<dynamic>> rows = [];


    rows.add(['Worker Attendance Summary']);
    rows.add(['Name', widget.record.name]);
    rows.add(['Email', widget.record.email]);
    rows.add(['Position', widget.record.role]);
    rows.add(['Work Type', widget.record.workType]);
    rows.add(['Attendance Type', widget.record.attendanceType]);
    rows.add([]);
    rows.add(['Total Working Days', '$_filteredTotal ${'days_unit'.tr()}']);
    rows.add(['Total Presents', '$_filteredPresents ${'days_unit'.tr()}']);
    rows.add(['Total Absents', '$_filteredAbsents ${'days_unit'.tr()}']);
    rows.add(['Total Leaves', '$_filteredLeaves ${'days_unit'.tr()}']);
    rows.add([
      'Attendance Percentage',
      '${_filteredPercentage.toStringAsFixed(1)}%',
    ]);
    rows.add([]);


    rows.add(['Daily Attendance Logs']);
    rows.add([
      'Date',
      'Status',
      'Work Model',
      'Attendance Type',
      'Reason/Notes',
    ]);


    final sortedRecords = List<Map<String, dynamic>>.from(_filteredRecords);
    sortedRecords.sort((a, b) {
      final aTime = a['createdAt'];
      final bTime = b['createdAt'];
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      if (aTime is Timestamp && bTime is Timestamp) {
        return bTime.compareTo(aTime);
      }
      return 0;
    });

    String formatDate(dynamic createdAt) {
      if (createdAt == null) return 'N/A';
      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      }
      if (createdAt is String) {
        try {
          final date = DateTime.parse(createdAt);
          return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        } catch (_) {
          return createdAt;
        }
      }
      return createdAt.toString();
    }

    for (var att in sortedRecords) {
      final dateStr = formatDate(att['createdAt']);
      final status = att['status'] ?? '-';
      final model = att['workType'] ?? '-';
      final type = att['attendanceType'] ?? '-';
      final notes = att['desc'] ?? att['reason'] ?? '-';
      rows.add([dateStr, status, model, type, notes]);
    }

    final csvString = const CsvEncoder().convert(rows);

    try {
      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'export_attendance'.tr(),
        fileName: '${widget.record.name.replaceAll(' ', '_')}_attendance.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csvString)),
      );

      if (outputFile == null) return;

      final file = File(outputFile);
      await file.writeAsString(csvString);

      if (context.mounted) {
        await OpenFile.open(outputFile);
        FlashySnackBar.show(context, message: 'attendance_exported'.tr());
      }
    } catch (e) {
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_exporting_csv'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    }
  }
}
