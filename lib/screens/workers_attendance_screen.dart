import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import 'home_screen.dart';
import '../utils/logout_dialog.dart';

// --- STYLING CONSTANTS ---
const Color primaryBlue = Color(0xFF0B51C1);
const Color bgGray = Color(0xFFF7F8FA);
const Color cardLightGray = Color(0xFFF3F5F8);
const Color textDark = Color(0xFF000000);
const Color textMuted = Color(0xFF000000);

const Color greenPresent = Color(0xFF00FF2A);
const Color redAbsent = Color(0xFFFF0004);
const Color orangeLeave = Color(0xFFFF7B00);
const Color pillGray = Color(0xFFE2E5EA);

class WorkersAttendanceScreen extends StatefulWidget {
  const WorkersAttendanceScreen({super.key});

  @override
  State<WorkersAttendanceScreen> createState() =>
      _WorkersAttendanceScreenState();
}

class _WorkersAttendanceScreenState extends State<WorkersAttendanceScreen> {
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _todayAttendance = [];
  bool _isLoading = true;
  String? _errorMessage;
  final FirestoreService _firestore = FirestoreService();
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;

  @override
  void dispose() {
    _workersSub?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _workers = DummyData.attendance;
        _todayAttendance = DummyData.attendance;
        _isLoading = false;
      });
      return;
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

  List<Map<String, dynamic>> get _filteredWorkers {
    return _workers.where((worker) {
      final name = (worker["name"] ?? "").toString().toLowerCase();
      final role = (worker["role"] ?? "").toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || role.contains(query);
      if (_selectedStatusFilter == 'All') return matchesSearch;
      return matchesSearch && (worker["status"] ?? "") == _selectedStatusFilter;
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
              _errorMessage!,
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
          SidebarWidget(
            selectedIndex: 2,
            selectedSubIndex: 0,
            isGuest: AuthService().currentUser?.isAnonymous ?? false,
            onItemSelected: (index, {subIndex}) {
              Navigator.of(context).pop();
            },
          ),
          // Right Main Content
          Expanded(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 32),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Left List Section: Worker Attendance Statuses
                              Expanded(
                                flex: 70,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Worker Attendance",
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
                                            4,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFEEEEEE),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            if (filteredWorkers.isEmpty)
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  40.0,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    "No Workers Found",
                                                    style: TextStyle(
                                                      color: Color(0xFF000000),
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontFamily:
                                                          'SF Pro Display',
                                                    ),
                                                  ),
                                                ),
                                              )
                                            else
                                              ...filteredWorkers.map(
                                                (worker) => WorkerListItem(
                                                  data: worker,
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            const PaginationWidget(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              // Right List Section: Today Detailed Attendance Logs
                              Expanded(
                                flex: 30,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Today Attendance",
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
                                            4,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFEEEEEE),
                                          ),
                                        ),
                                        child: Column(
                                          children: _todayAttendance.isEmpty
                                              ? [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          40.0,
                                                        ),
                                                    child: Center(
                                                      child: Text(
                                                        "No Attendance Records",
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF000000,
                                                          ),
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontFamily:
                                                              'SF Pro Display',
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ]
                                              : _todayAttendance
                                                    .map(
                                                      (att) =>
                                                          TodayAttendanceItem(
                                                            data: att,
                                                          ),
                                                    )
                                                    .toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
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
          const Text(
            "Workforce",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: textDark,
              fontFamily: 'SF Pro Display',
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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
                    const Text(
                      'Logout',
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
        borderRadius: BorderRadius.circular(8),
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
                });
              },
              decoration: InputDecoration(
                hintText: "Search by workers name / position",
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
}

void _showMarkAttendanceDialog(
  BuildContext context,
  Map<String, dynamic> data,
) {
  final name = data["name"] ?? "";
  final email = data["email"] ?? "";
  showDialog(
    context: context,
    barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
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
                  decoration: const BoxDecoration(color: Color(0xFF004FDE)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Mark Attendance',
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SF Pro Display',
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
                          image: const DecorationImage(
                            image: AssetImage('assets/profile_placeholder.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.phone,
                                    color: Color(0xFFFFFFFF),
                                    size: 16,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    '123 5434567',
                                    style: TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 14,
                                      fontFamily: 'SF Pro Display',
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
                            child: _buildToggleChip(
                              'Present',
                              'assets/present.svg',
                              const Color(0xFF00C853),
                              isSelected: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildToggleChip(
                              'Absent',
                              'assets/absent.svg',
                              const Color(0xFFF44336),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildToggleChip(
                              'Leave',
                              'assets/leave.svg',
                              const Color(0xFFFF9800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Reason (Required)',
                        style: TextStyle(
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
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const TextField(
                          maxLines: null,
                          decoration: InputDecoration.collapsed(
                            hintText: 'Enter reason......',
                            hintStyle: TextStyle(
                              color: Colors.black38,
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
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              minimumSize: const Size(0, 40),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F52BA),
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
                            child: const Text(
                              'Save',
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
      );
    },
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
      borderRadius: BorderRadius.circular(4),
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
            color: isSelected ? Color(0xFFFFFFFF) : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    ),
  );
}

class WorkerListItem extends StatelessWidget {
  final Map<String, dynamic> data;

  const WorkerListItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardLightGray,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage: const AssetImage('assets/profile_placeholder.png'),
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
                    overflow: TextOverflow.ellipsis,
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
                    overflow: TextOverflow.ellipsis,
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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(right: 16.0),
                child: StatusPill(status: (data["status"] ?? '').toString()),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showMarkAttendanceDialog(context, data),
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

  const TodayAttendanceItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardLightGray,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: const AssetImage(
                  'assets/profile_placeholder.png',
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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(status: (data["status"] ?? '').toString()),
            ],
          ),
          if (data["type"] != null) ...[
            const SizedBox(height: 12),
            Text(
              "Absent Type: ${data["type"]}",
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
                overflow: TextOverflow.ellipsis,
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
    Color bgColor;
    Color textColor = Color(0xFFFFFFFF);

    if (status == "*****") {
      bgColor = pillGray;
      textColor = textDark;
    } else if (status == "Present") {
      bgColor = greenPresent;
    } else if (status == "Absent") {
      bgColor = redAbsent;
    } else if (status == "Leave") {
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
        status,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          fontFamily: 'SF Pro Display',
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class PaginationWidget extends StatelessWidget {
  const PaginationWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Icon(Icons.chevron_left, size: 24, color: textDark),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: primaryBlue,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            "1",
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.chevron_right, size: 24, color: textDark),
      ],
    );
  }
}
