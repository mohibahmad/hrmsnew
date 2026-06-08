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
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: const AssetImage('assets/profile_placeholder.png'),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'SF Pro Display')),
                      const SizedBox(height: 4),
                      Text(record.email, style: const TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'SF Pro Display')),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 32),
              _previewRow('Role', record.role),
              _previewRow('Attendance Type', record.attendanceType),
              _previewRow('Work Type', record.workType),
              _previewRow('Status', record.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey, fontFamily: 'SF Pro Display')),
          ),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display')),
        ],
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

  static Widget _tableHeader(String title) {
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
