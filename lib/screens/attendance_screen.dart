import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file_plus/open_file_plus.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/attendance_service.dart';

import '../widgets/custom_timeframe_dropdown.dart';
import 'workers_attendance_screen.dart';
import '../utils/image_utils.dart';
import '../utils/date_utils.dart';
import '../utils/delete_dialog.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';

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

  const AttendanceScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _searchQuery = '';
  String _selectedTab = 'All';
  String _selectedTimeframe = 'Week';
  List<Map<String, dynamic>> _attendanceDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawAttendanceDocs = [];
  bool _isLoading = true;
  bool _workersLoaded = false;
  bool _attendanceLoaded = false;
  int _totalCount = 0;
  int _presentCount = 0;
  int _absentCount = 0;
  int _leaveCount = 0;
  int _currentPage = 1;
  static const int _itemsPerPage = 8;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _workersSub;

  @override
  void dispose() {
    _attendanceSub?.cancel();
    _workersSub?.cancel();
    super.dispose();
  }

  void _combineAttendance() {
    _attendanceDocs = AttendanceService.combineAttendance(
      workersList: _workersList,
      rawAttendanceDocs: _rawAttendanceDocs,
    );
    if (_workersLoaded && _attendanceLoaded) {
      _isLoading = false;
    }
    _totalCount = _attendanceDocs.where((d) => _matchesPeriod(d)).length;
    _presentCount = _attendanceDocs
        .where((d) => d['status'] == 'Present' && _matchesPeriod(d))
        .length;
    _absentCount = _attendanceDocs
        .where((d) => d['status'] == 'Absent' && _matchesPeriod(d))
        .length;
    _leaveCount = _attendanceDocs
        .where((d) => d['status'] == 'Leave' && _matchesPeriod(d))
        .length;
  }

  @override
  void initState() {
    super.initState();
    _attendanceDocs = [];
    _workersList = [];
    _rawAttendanceDocs = [];
    _isLoading = true;
    _workersLoaded = false;
    _attendanceLoaded = false;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = FirestoreService().workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workersList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _workersLoaded = true;
            _combineAttendance();
          });
        }
      }, onError: (e) {
        debugPrint('workersStream error: $e');
        if (mounted) {
          setState(() {
            _workersLoaded = true;
            _isLoading = false;
          });
        }
      });
      _attendanceSub = FirestoreService().attendanceStream.listen(
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
          debugPrint('attendanceStream error: $e');
          if (mounted) {
            setState(() {
              _attendanceLoaded = true;
              _isLoading = false;
            });
          }
        },
      );
    } else {
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawAttendanceDocs = List<Map<String, dynamic>>.from(
        DummyData.attendance,
      );
      _workersLoaded = true;
      _attendanceLoaded = true;
      _combineAttendance();
    }
  }

  bool _matchesPeriod(Map<String, dynamic> doc) {
    final createdAt = doc['createdAt'];
    final dateStr = createdAt?.toString() ?? '';
    if (dateStr.isEmpty) return true;
    return AppDateUtils.isDateWithinPeriod(dateStr, _selectedTimeframe);
  }

  List<Map<String, dynamic>> get _filteredRecords {
    return _attendanceDocs.where((doc) {
      if (!_matchesPeriod(doc)) return false;

      final name = (doc['name'] ?? '').toString().toLowerCase();
      final role = (doc['role'] ?? '').toString().toLowerCase();
      final status = (doc['status'] ?? '').toString();
      final query = _searchQuery.toLowerCase();

      final matchesSearch = name.contains(query) || role.contains(query);
      if (!matchesSearch) return false;

      if (_selectedTab == 'All') return true;
      if (_selectedTab == 'Present') return status == 'Present';
      if (_selectedTab == 'Absent') return status == 'Absent';
      if (_selectedTab == 'Leaves') return status == 'Leave';
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: bgGray,
      body: Column(
        children: [
          // Top Header Widget
          _buildHeader(context),
          // Main Body Content
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
                  _buildFilterAndDropdownRow(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left side: Attendance Table/Empty State
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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

                      // Right side timeframe dropdown popup (anchored or expanded)
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
          // Notification Bell
          GestureDetector(
            onTap: widget.onNotificationTap,
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
          GestureDetector(
            onTap: widget.onProfileTap,
            child: const UserAvatar(),
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
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _currentPage = 1;
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
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _searchQuery = '';
                        _currentPage = 1;
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
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const WorkersAttendanceScreen(),
                  transitionsBuilder: (_, __, ___, child) => child,
                  transitionDuration: Duration.zero,
                ),
              );
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
            count: "$_totalCount",
            iconAsset: 'assets/total_workers.svg',
            countColor: const Color(0xFF0247C4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'present_workers'.tr(),
            count: "$_presentCount",
            iconAsset: 'assets/present.svg',
            countColor: const Color(0xFF00FF2A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'absent_workers'.tr(),
            count: "$_absentCount",
            iconAsset: 'assets/absent.svg',
            countColor: const Color(0xFFFF0004),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'leave_workers'.tr(),
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
                ),
              ],
            ),
          ),
          SvgPicture.asset(iconAsset, height: 28, width: 28),
        ],
      ),
    );
  }

  Widget _buildFilterAndDropdownRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left Tabs
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              _buildTab('All', 'all_tab'.tr()),
              _buildTab('Present', 'present_tab'.tr()),
              _buildTab('Absent', 'absent_tab'.tr()),
              _buildTab('Leaves', 'leaves_tab'.tr()),
            ],
          ),
        ),

        // Right Dropdown Header
        CustomTimeframeDropdown(
          selectedPeriod: _selectedTimeframe,
          onChanged: (value) {
            setState(() {
              _selectedTimeframe = value;
              _currentPage = 1;
              final isGuest = AuthService().currentUser?.isAnonymous ?? false;
              if (isGuest) {
                _attendanceDocs = List<Map<String, dynamic>>.from(
                  DummyData.attendance,
                );
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildTab(String filterKey, String displayLabel) {
    final bool isActive = _selectedTab == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = filterKey;
          _currentPage = 1;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
              isSearchEmpty ? 'no_search_results'.tr() : 'no_attendance_records'.tr(),
              style: TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
            if (isSearchEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() { _searchQuery = ''; _currentPage = 1; }),
                icon: const Icon(Icons.close, size: 16),
                label: Text('clear_search'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TapDownDetails? _tapPosition;

  Future<void> _showRowMenu(
    BuildContext context,
    Map<String, dynamic> doc,
  ) async {
    final renderObj = context.findRenderObject();
    final RenderBox? button = renderObj is RenderBox ? renderObj : null;
    final overlayObj = Overlay.of(context).context.findRenderObject();
    final RenderBox? overlay = overlayObj is RenderBox ? overlayObj : null;
    if (overlay == null) return;

    final docId = doc['id'] as String;

    final value = await showMenu<String>(
      context: context,
      position: _tapPosition != null
          ? RelativeRect.fromRect(
              Rect.fromLTWH(
                _tapPosition!.globalPosition.dx,
                _tapPosition!.globalPosition.dy,
                0,
                0,
              ),
              Offset.zero & overlay.size,
            )
          : (button != null
                ? RelativeRect.fromRect(
                    Rect.fromPoints(
                      button.localToGlobal(Offset.zero, ancestor: overlay),
                      button.localToGlobal(
                        button.size.bottomRight(Offset.zero),
                        ancestor: overlay,
                      ),
                    ),
                    Offset.zero & overlay.size,
                  )
                : RelativeRect.fromRect(
                    Rect.fromLTWH(
                      overlay.size.width / 2,
                      overlay.size.height / 2,
                      0,
                      0,
                    ),
                    Offset.zero & overlay.size,
                  )),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFCBCBCB)),
      ),
      color: const Color(0xFFFBFBFC),
      items: [
        PopupMenuItem(
          value: 'preview',
          child: Row(
            children: [
              Icon(Icons.visibility, size: 18, color: Colors.black),
              SizedBox(width: 8),
              Text('preview'.tr(), style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/delete_icon.svg',
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  Colors.red,
                  BlendMode.srcIn,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'delete'.tr(),
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );

    if (value == 'preview') {
      _showAttendancePreview(context, doc);
    } else if (value == 'delete') {
      final confirmed = await DeleteDialog.show(
        context: context,
        title: 'delete_attendance_record'.tr(),
        content: 'delete_attendance_desc'.tr(),
      );
      if (!confirmed) return;

      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        setState(() {
          final doc = _attendanceDocs.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a?['id'] == docId,
            orElse: () => null,
          );
          if (doc == null) return;
          final email = doc['email']?.toString();
          if (email != null && email.isNotEmpty) {
            DummyData.workers.removeWhere(
              (w) =>
                  (w['email'] ?? '').toString().toLowerCase() ==
                  email.toLowerCase(),
            );
            DummyData.attendance.removeWhere(
              (a) =>
                  (a['email'] ?? '').toString().toLowerCase() ==
                  email.toLowerCase(),
            );
          } else {
            _attendanceDocs.removeWhere((a) => a['id'] == docId);
            DummyData.attendance.removeWhere((a) => a['id'] == docId);
          }
          DummyData.saveToPrefs();
          _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
          _rawAttendanceDocs = List<Map<String, dynamic>>.from(
            DummyData.attendance,
          );
          _combineAttendance();
        });
      } else {
        final docId = doc['id'] as String;
        if (!docId.startsWith('norecord_')) {
          await FirestoreService().deleteAttendanceRecord(docId);
        }
      }
    }
  }

  void _showAttendancePreview(BuildContext context, Map<String, dynamic> doc) {
    final email = (doc['email'] ?? '').toString().trim().toLowerCase();
    final name = (doc['name'] ?? '').toString().trim().toLowerCase();

    final workerRecords = _rawAttendanceDocs.where((att) {
      final attEmail = (att['email'] ?? '').toString().trim().toLowerCase();
      final attName = (att['name'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        return attEmail == email && attName == name;
      }
      return name.isNotEmpty && attName == name;
    }).toList();

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
    final totalPages = (records.isEmpty)
        ? 1
        : (records.length / _itemsPerPage).ceil();
    final safeStartIndex = (_currentPage - 1) * _itemsPerPage >= records.length
        ? 0
        : (_currentPage - 1) * _itemsPerPage;
    final paginatedRecords = records.isEmpty
        ? <Map<String, dynamic>>[]
        : records.sublist(
            safeStartIndex,
            (safeStartIndex + _itemsPerPage) > records.length
                ? records.length
                : (safeStartIndex + _itemsPerPage),
          );

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
          // Table Header
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
          // Table Rows
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: paginatedRecords.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = paginatedRecords[index];
                final name = (doc['name'] ?? '').toString();
                final email = (doc['email'] ?? '').toString();
                final role = (doc['role'] ?? '').toString();
                final status = (doc['status'] ?? '').toString();
                final attendanceType = (doc['attendanceType'] ?? 'Remote')
                    .toString();
                final workType = (doc['workType'] ?? 'Full Time').toString();

                final localizeAttendanceType = LocalizationHelper.localizeAttendanceType;
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
                              CircleAvatar(
                                radius: 20,
                                backgroundImage: getProfileImage(
                                  doc['profileImage']?.toString(),
                                  email,
                                  index,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Tooltip(
                                      message: name,
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: textDark,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        maxLines: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Tooltip(
                                      message: email,
                                      child: Text(
                                        email,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
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
                          child: Tooltip(
                            message: status.isEmpty
                                ? '-'
                                : status.toLowerCase().tr(),
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
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24.0),
                          child: Tooltip(
                            message: localizeWorkType(workType),
                            child: Text(
                              localizeWorkType(workType),
                              style: const TextStyle(
                                fontSize: 15,
                                color: textDark,
                                fontFamily: 'SF Pro Display',
                              ),
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Tooltip(
                          message: role,
                          child: Text(
                            role,
                            style: const TextStyle(
                              fontSize: 15,
                              color: textDark,
                              fontFamily: 'SF Pro Display',
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: GestureDetector(
                          onTapDown: (details) {
                            _tapPosition = details;
                          },
                          onTap: () => _showRowMenu(context, doc),
                          child: const Icon(
                            Icons.more_vert,
                            color: Colors.black,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Pagination
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_left,
                    color: _currentPage > 1
                        ? Colors.black
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_right,
                    color: _currentPage < totalPages
                        ? Colors.black
                        : Colors.grey.shade400,
                  ),
                ),
              ],
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

class WorkerAttendancePreviewCard extends StatelessWidget {
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
            ],
          ),
        ),
        Container(
          color: const Color(0xFF0247C4),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFFFFFFFF), width: 2),
                  image: DecorationImage(
                    image: getProfileImage(
                      record.profileImage,
                      record.email,
                      0,
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        record.workType,
                        style: const TextStyle(
                          color: Color(0xFF0A51D0),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          color: Color(0xFFFFFFFF),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message: record.email,
                            child: Text(
                              record.email,
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.phone,
                            color: Color(0xFFFFFFFF),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            record.phone ?? 'na'.tr(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            softWrap: true,
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
              value: '$presents',
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
              value: '$absents',
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
              value: '$leaves',
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildDetailCard(
                title: 'attendance_label'.tr(),
                rows: [
                  _buildDetailRow(
                    'total_working_days'.tr(),
                    '$totalWorkingDays ${'days_unit'.tr()}',
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'total_presents'.tr(),
                    '$presents ${'days_unit'.tr()}',
                    darkGreen,
                  ),
                  _buildDetailRow(
                    'total_absents'.tr(),
                    '$absents ${'days_unit'.tr()}',
                    darkRed,
                  ),
                  _buildDetailRow(
                    'total_leaves'.tr(),
                    '$leaves ${'days_unit'.tr()}',
                    darkOrange,
                  ),
                  _buildDetailRow(
                    'attendance_percentage'.tr(),
                    '${percentage.toStringAsFixed(1)}%',
                    primaryBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDetailCard(
                title: 'worker_information'.tr(),
                rows: [
                  _buildDetailRow(
                    'position'.tr(),
                    record.role,
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'work_type'.tr(),
                    record.localizedWorkType,
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'attendance_type'.tr(),
                    record.localizedAttendanceType,
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
      padding: const EdgeInsets.all(10),
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
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final List<List<dynamic>> rows = [];

    // Header section
    rows.add(['Worker Attendance Summary']);
    rows.add(['Name', record.name]);
    rows.add(['Email', record.email]);
    rows.add(['Position', record.role]);
    rows.add(['Work Type', record.workType]);
    rows.add(['Attendance Type', record.attendanceType]);
    rows.add([]);
    rows.add(['Total Working Days', '$totalWorkingDays ${'days_unit'.tr()}']);
    rows.add(['Total Presents', '$presents ${'days_unit'.tr()}']);
    rows.add(['Total Absents', '$absents ${'days_unit'.tr()}']);
    rows.add(['Total Leaves', '$leaves ${'days_unit'.tr()}']);
    rows.add(['Attendance Percentage', '${percentage.toStringAsFixed(1)}%']);
    rows.add([]);

    // Daily Logs header
    rows.add(['Daily Attendance Logs']);
    rows.add([
      'Date',
      'Status',
      'Work Model',
      'Attendance Type',
      'Reason/Notes',
    ]);

    // Sort workerRecords by date (newest first)
    final sortedRecords = List<Map<String, dynamic>>.from(workerRecords);
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
        fileName: '${record.name.replaceAll(' ', '_')}_attendance.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
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
