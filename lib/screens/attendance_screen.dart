import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'workers_attendance_screen.dart';

// --- STYLING CONSTANTS (Curated HSL/Hex Harmonious Palette) ---
const Color primaryBlue = Color(0xFF0B51C1);
const Color lightBlueBg = Color(0xFFE8F0FE);
const Color bgGray = Color(0xFFF8FAFC);
const Color textDark = Color(0xFF0F172A);
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

  AttendanceRecord({
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.attendanceType = 'Remote',
    this.workType = 'Full Time',
  });
}

class AttendanceScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;

  const AttendanceScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _searchQuery = '';
  String _selectedTab = 'All'; // 'All', 'Present', 'Absent', 'Leaves'
  String _selectedTimeframe =
      'Week'; // 'Week', 'Month', '3 Month', '6 Month', 'Yearly'
  bool _isTimeframeDropdownOpen = false;

  final List<AttendanceRecord> _mockRecords = [
    AttendanceRecord(
      name: 'Olivia Vance',
      email: 'oliva23abs@gmail.com',
      role: 'Designer',
      status: 'Present',
      attendanceType: 'Remote',
      workType: 'Full Time',
    ),
    AttendanceRecord(
      name: 'Sophia Smith',
      email: 'sophia.smith@gmail.com',
      role: 'Developer',
      status: 'Absent',
      attendanceType: 'On-Site',
      workType: 'Remote',
    ),
    AttendanceRecord(
      name: 'Liam Vance',
      email: 'liam.vance@gmail.com',
      role: 'Designer',
      status: 'Present',
      attendanceType: 'Remote',
      workType: 'Hybrid',
    ),
    AttendanceRecord(
      name: 'Amelia Gray',
      email: 'amelia123@gmail.com',
      role: 'Designer',
      status: 'Leave',
      attendanceType: 'On-Site',
      workType: 'Full Time',
    ),
    AttendanceRecord(
      name: 'Jackson Miller',
      email: 'jackson@gmail.com',
      role: 'Developer',
      status: 'Present',
      attendanceType: 'On-Site',
      workType: 'Full Time',
    ),
  ];

  List<AttendanceRecord> get _filteredRecords {
    return _mockRecords.where((record) {
      // Search matching
      final matchesSearch =
          record.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          record.role.toLowerCase().contains(_searchQuery.toLowerCase());

      // Tab matching
      if (_selectedTab == 'All') {
        return matchesSearch;
      } else if (_selectedTab == 'Present') {
        return matchesSearch && record.status == 'Present';
      } else if (_selectedTab == 'Absent') {
        return matchesSearch && record.status == 'Absent';
      } else if (_selectedTab == 'Leaves') {
        return matchesSearch && record.status == 'Leave';
      }
      return matchesSearch;
    }).toList();
  }

  int get _totalCount => _mockRecords.length;
  int get _presentCount =>
      _mockRecords.where((r) => r.status == 'Present').length;
  int get _absentCount =>
      _mockRecords.where((r) => r.status == 'Absent').length;
  int get _leaveCount => _mockRecords.where((r) => r.status == 'Leave').length;

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
                            const Text(
                              "Today Attendance",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textDark,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (filtered.isEmpty)
                              _buildEmptyState()
                            else
                              _buildAttendanceTable(filtered),
                          ],
                        ),
                      ),

                      // Right side timeframe dropdown popup (anchored or expanded)
                      if (_isTimeframeDropdownOpen) ...[
                        const SizedBox(width: 20),
                        _buildTimeframeDropdown(),
                      ],
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
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Workforce',
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Track and manage workforce daily attendance logs.',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          const Spacer(),
          // Notification Bell
          SvgPicture.asset(
            'assets/notification_icon.svg',
            height: 24,
            width: 24,
            colorFilter: const ColorFilter.mode(
              Color(0xFF0F172A),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: CircleAvatar(
              radius: 19,
              backgroundImage: const AssetImage('assets/profileimage.png'),
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
              color: Colors.white,
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
                        hintText: "Search by workers name",
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
          ),
        ),
        const SizedBox(width: 24),
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
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: const Text(
              "Workers Attendance",
              style: TextStyle(
                color: Colors.white,
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
            title: "Total Workers",
            count: "$_totalCount",
            iconAsset: 'assets/total_workers.svg',
            countColor: const Color(0xFF0247C4),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildSummaryCard(
            title: "Present Workers",
            count: "$_presentCount",
            iconAsset: 'assets/present.svg',
            countColor: const Color(0xFF00FF2A),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildSummaryCard(
            title: "Absent Workers",
            count: "$_absentCount",
            iconAsset: 'assets/absent.svg',
            countColor: const Color(0xFFFF0004),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildSummaryCard(
            title: "Leave Workers",
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              _buildTab("All"),
              _buildTab("Present"),
              _buildTab("Absent"),
              _buildTab("Leaves"),
            ],
          ),
        ),

        // Right Dropdown Header
        GestureDetector(
          onTap: () {
            setState(() {
              _isTimeframeDropdownOpen = !_isTimeframeDropdownOpen;
            });
          },
          child: Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(6),
                topRight: const Radius.circular(6),
                bottomLeft: Radius.circular(_isTimeframeDropdownOpen ? 0 : 6),
                bottomRight: Radius.circular(_isTimeframeDropdownOpen ? 0 : 6),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedTimeframe == 'Week' ? 'Today' : _selectedTimeframe,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                Icon(
                  _isTimeframeDropdownOpen
                      ? Icons.arrow_drop_up
                      : Icons.arrow_drop_down,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String text) {
    final bool isActive = _selectedTab == text;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.white : textDark,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }

  Widget _buildTimeframeDropdown() {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRadioItem("Week"),
          _buildRadioItem("Month"),
          _buildRadioItem("3 Month"),
          _buildRadioItem("6 Month"),
          _buildRadioItem("Yearly"),
        ],
      ),
    );
  }

  Widget _buildRadioItem(String text) {
    final bool isActive = _selectedTimeframe == text;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTimeframe = text;
          _isTimeframeDropdownOpen = false;
        });
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? primaryBlue : Colors.grey.shade400,
                  width: 1.5,
                ),
              ),
              child: isActive
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isActive ? primaryBlue : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/placeholder_workers.svg',
              width: 120,
              height: 100,
            ),
            const SizedBox(height: 16),
            const Text(
              "No Attendance Records",
              style: TextStyle(
                color: primaryBlue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try adjusting your filters or search query.",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }

  TapDownDetails? _tapPosition;

  void _showRowMenu(BuildContext context, AttendanceRecord record) {
    if (_tapPosition == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(_tapPosition!.globalPosition.dx, _tapPosition!.globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'preview', child: Row(
          children: [
            Icon(Icons.visibility, size: 18, color: Colors.black87),
            SizedBox(width: 8),
            Text('Preview', style: TextStyle(fontSize: 14)),
          ],
        )),
        const PopupMenuItem(value: 'delete', child: Row(
          children: [
            Icon(Icons.delete_outline, size: 18, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete', style: TextStyle(fontSize: 14, color: Colors.red)),
          ],
        )),
      ],
    ).then((value) {
      if (value == 'preview') {
        _showAttendancePreview(context, record);
      }
    });
  }

  void _showAttendancePreview(BuildContext context, AttendanceRecord record) {
    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: WorkerAttendancePreviewCard(record: record),
      ),
    );
  }

  Widget _buildAttendanceTable(List<AttendanceRecord> records) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          // Table Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(flex: 3, child: _tableHeader('Worker Name')),
                Expanded(flex: 2, child: _tableHeader('Attendance Type')),
                Expanded(flex: 2, child: _tableHeader('Status')),
                Expanded(flex: 2, child: _tableHeader('Work Type')),
                Expanded(flex: 2, child: _tableHeader('Position')),
                const SizedBox(width: 24),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // Table Rows
          ...List.generate(records.length, (index) {
            final record = records[index];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: const AssetImage(
                                'assets/profile_placeholder.png',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: textDark,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    record.email,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          record.attendanceType,
                          style: const TextStyle(
                            fontSize: 14,
                            color: textDark,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          record.status,
                          style: TextStyle(
                            color: record.status == 'Present'
                                ? greenPresent
                                : (record.status == 'Absent' ? redAbsent : orangeLeave),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          record.workType,
                          style: const TextStyle(
                            fontSize: 14,
                            color: textDark,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          record.role,
                          style: const TextStyle(
                            fontSize: 14,
                            color: textDark,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTapDown: (details) {
                          _tapPosition = details;
                        },
                        onTap: () => _showRowMenu(context, record),
                        child: const Icon(Icons.more_vert, color: Colors.black87, size: 24),
                      ),
                    ],
                  ),
                ),
                if (index < records.length - 1)
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
              ],
            );
          }),
          const SizedBox(height: 16),
          // Pagination
          Padding(
            padding: const EdgeInsets.only(right: 24, bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.chevron_left, color: Colors.black54),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.black54),
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
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: textDark,
        fontFamily: 'SF Pro Display',
      ),
    );
  }
}

class WorkerAttendancePreviewCard extends StatelessWidget {
  final AttendanceRecord record;

  const WorkerAttendancePreviewCard({super.key, required this.record});

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
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
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
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Text(
                'Worker Attendance Preview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                icon: SvgPicture.asset(
                  'assets/share1.svg',
                  height: 18,
                  width: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
                  border: Border.all(color: Colors.white, width: 2),
                  image: const DecorationImage(
                    image: AssetImage('assets/profile_placeholder.png'),
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
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        record.workType,
                        style: const TextStyle(
                          color: Color(0xFF0A51D0),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            record.email,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    Row(
                      children: [
                        const Icon(Icons.phone, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '123 5434567',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              )
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
              title: 'Total Presents',
              value: '112',
              bgColor: lightGreenBg,
              iconColor: darkGreen,
              iconBuilder: (color) => _buildPresentIcon(color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'Total Absent',
              value: '10',
              bgColor: lightRedBg,
              iconColor: darkRed,
              iconBuilder: (color) => _buildAbsentIcon(color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'Total Leaves',
              value: '4',
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
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
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Days',
                  style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          )
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
          Align(alignment: Alignment.topLeft, child: Icon(Icons.person, color: color, size: 28)),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
          Align(alignment: Alignment.topLeft, child: Icon(Icons.person, color: color, size: 28)),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
          Align(alignment: Alignment.topLeft, child: Icon(Icons.person, color: color, size: 28)),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
          SizedBox(
            width: 214,
            child: _buildDetailCard(
              title: 'Attendance',
              rows: [
                _buildDetailRow('Total Working Days', '132 Days', Colors.black),
                _buildDetailRow('Total Presents', '112 Days', darkGreen),
                _buildDetailRow('Total Absents', '8 Days', darkRed),
                _buildDetailRow('Total Leaves', '12 Days', darkOrange),
                _buildDetailRow('Attendance %', '8.5%', primaryBlue),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 214,
            child: _buildDetailCard(
              title: 'Worker Information',
              rows: [
                _buildDetailRow('Position', record.role, Colors.black),
                _buildDetailRow('Work Type', record.workType, Colors.black),
                _buildDetailRow('Attendance Type', record.attendanceType, Colors.black),
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
        color: Colors.white,
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
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
