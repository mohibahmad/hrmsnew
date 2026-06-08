import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

// --- STYLING CONSTANTS ---
const Color primaryBlue = Color(0xFF0B51C1);
const Color bgGray = Color(0xFFF7F8FA);
const Color cardLightGray = Color(0xFFF3F5F8);
const Color textDark = Color(0xFF0F172A);
const Color textMuted = Colors.black;

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

  List<Map<String, dynamic>> _getWorkerData() {
    return [
      {
        "name": "Olivia Vance",
        "email": "oliva23abs@gmail.com",
        "role": "Web Developer",
        "status": "*****",
      },
      {
        "name": "Sophia Smith",
        "email": "sophia.smith@gmail.com",
        "role": "Marketing",
        "status": "*****",
      },
      {
        "name": "Liam Vance",
        "email": "liam.vance@gmail.com",
        "role": "Designer",
        "status": "*****",
      },
      {
        "name": "Jackson Miller",
        "email": "jackson@gmail.com",
        "role": "Engineering",
        "status": "Present",
      },
      {
        "name": "Amelia Gray",
        "email": "amelia123@gmail.com",
        "role": "Sales",
        "status": "Absent",
      },
      {
        "name": "Olivia Vance",
        "email": "oliva23abs@gmail.com",
        "role": "Designer",
        "status": "Leave",
      },
      {
        "name": "Ava Martinez",
        "email": "ava@gmail.com",
        "role": "Designer",
        "status": "Present",
      },
      {
        "name": "Lucas Johnson",
        "email": "lucas@gmail.com",
        "role": "Engineering",
        "status": "Present",
      },
    ];
  }

  List<Map<String, dynamic>> _getTodayData() {
    return [
      {"name": "Amelia Gray", "status": "Present", "type": null, "desc": null},
      {
        "name": "Liam Vance",
        "status": "Absent",
        "type": "Sick Leave",
        "desc":
            "Taking medical rest as per physician's advice due to food poisoning.",
      },
      {
        "name": "Sophia Smith",
        "status": "Leave",
        "type": "Casual Leave",
        "desc": "Family emergency to attend. Will resume duty tomorrow.",
      },
      {"name": "Olivia Vance", "status": "Present", "type": null, "desc": null},
      {"name": "Ava Martinez", "status": "Present", "type": null, "desc": null},
      {
        "name": "Lucas Johnson",
        "status": "Present",
        "type": null,
        "desc": null,
      },
      {
        "name": "Jackson Miller",
        "status": "Leave",
        "type": "Casual Leave",
        "desc": null,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final filteredWorkers = _getWorkerData().where((worker) {
      final name = worker["name"].toString().toLowerCase();
      final role = worker["role"].toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || role.contains(query);
      
      if (_selectedStatusFilter == 'All') return matchesSearch;
      return matchesSearch && worker["status"] == _selectedStatusFilter;
    }).toList();

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
            onItemSelected: (index) {
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
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 32),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left List Section: Worker Attendance Statuses
                            Expanded(
                              flex: 65,
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
                                  _buildFilterChips(),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFFEEEEEE),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        if (filteredWorkers.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.all(40.0),
                                            child: Center(
                                              child: Text(
                                                "No Workers Found",
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          ...filteredWorkers
                                              .map(
                                                (worker) => WorkerListItem(
                                                  data: worker,
                                                ),
                                              )
                                              .toList(),
                                        const SizedBox(height: 8),
                                        const PaginationWidget(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 32),
                            // Right List Section: Today Detailed Attendance Logs
                            Expanded(
                              flex: 35,
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
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFFEEEEEE),
                                      ),
                                    ),
                                    child: Column(
                                      children: _getTodayData()
                                          .map(
                                            (att) =>
                                                TodayAttendanceItem(data: att),
                                          )
                                          .toList(),
                                    ),
                                  ),
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
      padding: const EdgeInsets.only(left: 32, right: 32, top: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
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
                color: Colors.black,
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
          SvgPicture.asset(
            'assets/notification_icon.svg',
            height: 24,
            width: 24,
            colorFilter: const ColorFilter.mode(
              Color(0xFF0F172A),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 24),
          // Clicking avatar menu also pops/navigates properly
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                AuthService().signOut();
                Navigator.of(context).pop();
              }
            },
            offset: const Offset(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            color: Colors.white,
            elevation: 8,
            tooltip: '',
            child: SvgPicture.asset(
              'assets/app_icon.svg',
              width: 42,
              height: 42,
              fit: BoxFit.contain,
            ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: TextField(
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        decoration: InputDecoration(
          hintText: "Search by workers name / position",
          hintStyle: TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(14),
            child: SvgPicture.asset(
              'assets/search icon.svg',
              height: 20,
              width: 20,
              colorFilter: const ColorFilter.mode(
                Colors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Present', 'Absent', 'Leave'];
    return Row(
      children: filters.map((filter) {
        final isActive = _selectedStatusFilter == filter;
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedStatusFilter = filter;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive ? primaryBlue : const Color(0xFFEEEEEE),
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: isActive ? Colors.white : textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

void _showMarkAttendanceDialog(BuildContext context, Map<String, dynamic> data) {
  final name = data["name"] ?? "";
  final email = data["email"] ?? "";
  showDialog(
    context: context,
    barrierColor: const Color(0xFF5A7BBB).withValues(alpha: 0.85),
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: 480,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
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
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40),
                    const Text(
                      'Mark Attendance',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display'),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
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
                        border: Border.all(color: Colors.white, width: 2),
                        image: const DecorationImage(
                          image: AssetImage('assets/profile_placeholder.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'SF Pro Display')),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.email, color: Colors.white, size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  email,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'SF Pro Display'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Row(
                            children: [
                              Icon(Icons.phone, color: Colors.white, size: 14),
                              SizedBox(width: 8),
                              Text('123 5434567', style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'SF Pro Display')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Body Section
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildToggleChip('Present', 'assets/present.svg', const Color(0xFF00C853), isSelected: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildToggleChip('Absent', 'assets/absent.svg', const Color(0xFFF44336))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildToggleChip('Leave', 'assets/leave.svg', const Color(0xFFFF9800))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Reason (Required)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'SF Pro Display')),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const TextField(
                        maxLines: null,
                        decoration: InputDecoration.collapsed(
                          hintText: 'Enter reason......',
                          hintStyle: TextStyle(color: Colors.black38, fontSize: 13, fontFamily: 'SF Pro Display'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            minimumSize: const Size(0, 40),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'SF Pro Display')),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F52BA),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            minimumSize: const Size(0, 40),
                            elevation: 0,
                          ),
                          child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'SF Pro Display')),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildToggleChip(String label, String svgAsset, Color iconColor, {bool isSelected = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: isSelected ? const Color(0xFF0F52BA) : Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: isSelected ? const Color(0xFF0F52BA) : Colors.grey.shade200),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          svgAsset,
          height: 18,
          width: 18,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
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
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data["name"],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data["email"],
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: pillGray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  data["role"],
                  style: const TextStyle(
                    fontSize: 13,
                    color: textDark,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(status: data["status"]),
            ),
          ),
          GestureDetector(
            onTap: () => _showMarkAttendanceDialog(context, data),
            child: SvgPicture.asset(
              'assets/edit_icon.svg',
              height: 20,
              width: 20,
              colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
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
              Text(
                data["name"],
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const Spacer(),
              StatusPill(status: data["status"]),
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
                data["desc"],
                style: const TextStyle(
                  fontSize: 12,
                  color: textMuted,
                  height: 1.3,
                  fontFamily: 'SF Pro Display',
                ),
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
    Color textColor = Colors.white;
    double hPadding = 16;

    if (status == "*****") {
      bgColor = pillGray;
      textColor = textDark;
      hPadding = 24;
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
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
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
              color: Colors.white,
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
