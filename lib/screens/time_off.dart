import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/firestore_service.dart';
import 'assign_time_off.dart';

class Worker {
  final String name;
  final String email;
  final String position;
  final String contact;
  final String action;
  final bool isMaleAvatar; // Used to mock the specific placeholder illustrations

  Worker(this.name, this.email, this.position, this.contact, this.action, this.isMaleAvatar);
}

class TimeOffScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onAssignTimeOff;

  const TimeOffScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onAssignTimeOff,
  });

  @override
  State<TimeOffScreen> createState() => _TimeOffScreenState();
}

class _TimeOffScreenState extends State<TimeOffScreen> {
  bool isDataEmpty = false;
  String _searchQuery = '';
  String _selectedTab = 'All';
  List<QueryDocumentSnapshot> _timeoffDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    FirestoreService().timeoffStream.listen((snapshot) {
      if (mounted) {
        setState(() {
          _timeoffDocs = snapshot.docs;
          _isLoading = false;
        });
      }
    });
  }

  List<QueryDocumentSnapshot> get _filteredWorkers {
    return _timeoffDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final position = (data['position'] ?? '').toString().toLowerCase();
      final email = (data['email'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      final matchesSearch = name.contains(query) ||
          position.contains(query) ||
          email.contains(query);
      
      if (!matchesSearch) return false;
      if (_selectedTab == 'All') return true;
      if (_selectedTab == 'Management') {
        return position.contains('manag');
      }
      return position.contains(_selectedTab.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWorkers;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 30),
                  const Text(
                    'Time off List',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterTabs(),
                  const SizedBox(height: 24),
                  isDataEmpty || filtered.isEmpty ? _buildEmptyState() : _buildDataTable(filtered),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
        ),
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
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage workforce time off and leave requests.',
                style: TextStyle(
                  color: Color(0xFF64748B),
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
              Color(0xFF000000),
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
      );
  }

  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabItem('All'),
          _buildTabItem('Designer'),
          _buildTabItem('Developer'),
          _buildTabItem('Engineering'),
          _buildTabItem('Sales'),
          _buildTabItem('Management'),
        ],
      ),
    );
  }

  Widget _buildTabItem(String text) {
    final bool isSelected = _selectedTab == text;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0247C4) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Color(0xFFFFFFFF) : const Color(0xFF000000),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(List<QueryDocumentSnapshot> workers) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          // Table Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Worker Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Position',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Contact no',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Time Off',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: workers.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
            itemBuilder: (context, index) {
              final doc = workers[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] ?? '').toString();
              final email = (data['email'] ?? '').toString();
              final position = (data['position'] ?? '').toString();
              final contact = (data['contact'] ?? '').toString();
              final action = (data['action'] ?? 'Payroll Data').toString();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Row(
                  children: [
                    // Worker Name with Avatar
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundImage: AssetImage('assets/profile_placeholder.png'),
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
                                    fontSize: 14,
                                    color: Color(0xFF000000),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Position
                    Expanded(
                      flex: 2,
                      child: Text(
                        position,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                    // Contact
                    Expanded(
                      flex: 2,
                      child: Text(
                        contact,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                    // Time Off Action
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          if (widget.onAssignTimeOff != null) {
                            widget.onAssignTimeOff!();
                          } else {
                            // Fallback if rendered as standalone
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => AssignTimeOffScreen(
                                  onBack: () => Navigator.of(context).pop(),
                                ),
                              ),
                            );
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Text(
                            action,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF0247C4),
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Pagination
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('1', style: TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.black54),
              ],
            ),
          )
        ],
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
              "No Time Off Requests",
              style: TextStyle(
                color: Color(0xFF0247C4),
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
}
