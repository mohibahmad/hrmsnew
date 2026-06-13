import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import 'pricing_screen.dart';

void main() {
  runApp(const WorkerManagementApp());
}

class WorkerManagementApp extends StatelessWidget {
  const WorkerManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worker Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: const Color(0xFFF9FAFC),
        useMaterial3: false,
      ),
      home: const MainLayoutScreen(),
    );
  }
}

// ==========================================
// MAIN LAYOUT (SIDEBAR + CONTENT SWITCHER)
// ==========================================
class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  // 0: Dashboard List, 1: Add Worker Form
  int _currentMenuIndex = 1;

  final Color sidebarBlue = const Color(0xFF0B50C3);
  final Color activeTabBlue = const Color(0xFF4C84E0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // --- LEFT SIDEBAR ---
          Container(
            width: 290,
            color: sidebarBlue,
            child: Column(
              children: [
                // Upgrade Pro Card
                if (!(AuthService().currentUser?.isAnonymous ?? false))
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        barrierColor: const Color(
                          0xFF0247C4,
                        ).withValues(alpha: 0.5),
                        builder: (context) => const SubscriptionDialog(),
                      );
                    },
                    child: Container(
                      width: 252,
                      height: 218,
                      margin: const EdgeInsets.only(
                        top: 29,
                        left: 19,
                        right: 19,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Color(0xFFFFFFFF),
                          width: 1.0,
                        ),
                        image: const DecorationImage(
                          image: AssetImage('assets/premium_bg.png'),
                          fit: BoxFit.cover,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xFFFFFFFF),
                            blurRadius: 0.5,
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
                              const Text(
                                'Upgrade Pro',
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildCheckItem('Unlock All Features'),
                          _buildCheckItem('No Commitment'),
                          _buildCheckItem('Cancel Anytime'),
                          const SizedBox(height: 10),
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.centerRight,
                            children: [
                              Container(
                                width: double.infinity,
                                height: 46,
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 52,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(0xFF000000),
                                  borderRadius: BorderRadius.circular(23),
                                  border: Border.all(
                                    color: Color(0xFFFFFFFF),
                                    width: 1.0,
                                  ),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Get to Pro',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro',
                                        height: 1.1,
                                      ),
                                    ),
                                    Text(
                                      'Subscribe Now',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro',
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: -3,
                                bottom: -3,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFFFFFF),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Image.asset(
                                    "assets/right_back_arrow.png",
                                    width: 20,
                                    height: 20,
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

                // Navigation Menu
                _buildNavItem(
                  Icons.grid_view_rounded,
                  'Dashboard',
                  _currentMenuIndex == 0,
                  onTap: () => setState(() => _currentMenuIndex = 0),
                ),
                _buildNavItem(
                  Icons.people_alt,
                  'Workers',
                  _currentMenuIndex == 1,
                  onTap: () => setState(() => _currentMenuIndex = 1),
                ),
                _buildNavItem(
                  Icons.engineering,
                  'Workforce',
                  false,
                  hasDropdown: true,
                ),
                _buildNavItem(Icons.receipt_long, 'Expenses', false),
                _buildNavItem(Icons.settings, 'Settings', false),
              ],
            ),
          ),

          // --- MAIN CONTENT ---
          Expanded(
            child: IndexedStack(
              index: _currentMenuIndex,
              children: [
                DashboardWorkerList(
                  onAddWorker: () => setState(() => _currentMenuIndex = 1),
                ), // Index 0
                AddNewWorkerFlow(
                  onBack: () => setState(() => _currentMenuIndex = 0),
                ), // Index 1
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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

  Widget _buildNavItem(
    IconData icon,
    String title,
    bool isActive, {
    bool hasDropdown = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 46,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? activeTabBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, color: Color(0xFFFFFFFF), size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 18,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFamily: 'SF Pro',
                      ),
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
          ),
          if (isActive)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  height: 26,
                  width: 6,
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

// ==========================================
// WORKERS DASHBOARD SCREEN SWITCHER
// ==========================================
class WorkersScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;

  const WorkersScreen({
    super.key,
    this.onLogout,
    this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  bool _isAddingWorker = false;
  Map<String, dynamic>? _workerToEdit;

  @override
  Widget build(BuildContext context) {
    if (_isAddingWorker) {
      return AddNewWorkerFlow(
        workerToEdit: _workerToEdit,
        onBack: () {
          setState(() {
            _isAddingWorker = false;
            _workerToEdit = null;
          });
        },
      );
    } else {
      return DashboardWorkerList(
        onAddWorker: () {
          setState(() {
            _isAddingWorker = true;
            _workerToEdit = null;
          });
        },
        onEditWorker: (worker) {
          setState(() {
            _isAddingWorker = true;
            _workerToEdit = worker;
          });
        },
        onLogout: widget.onLogout,
        onProfileTap: widget.onProfileTap,
        onNotificationTap: widget.onNotificationTap,
      );
    }
  }
}

// ==========================================
// DASHBOARD WORKER LIST
// ==========================================
class DashboardWorkerList extends StatefulWidget {
  final VoidCallback onAddWorker;
  final ValueChanged<Map<String, dynamic>>? onEditWorker;
  final VoidCallback? onLogout;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;

  const DashboardWorkerList({
    super.key,
    required this.onAddWorker,
    this.onEditWorker,
    this.onLogout,
    this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<DashboardWorkerList> createState() => _DashboardWorkerListState();
}

class _DashboardWorkerListState extends State<DashboardWorkerList> {
  final Color actionBtnBlue = const Color(0xFF0E53C5);
  final Color buttonColor = const Color(0xFF0C51C1);
  final Color textDark = const Color(0xFF000000);
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _allWorkers = [];
  bool _isLoading = true;
  int _currentPage = 1;
  static const int _itemsPerPage = 5;
  StreamSubscription? _workersSub;

  @override
  void dispose() {
    _workersSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _allWorkers = [];
    _isLoading = true;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = FirestoreService().workersStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _allWorkers = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    } else {
      _allWorkers = DummyData.workers;
      _isLoading = false;
    }
  }

  bool _matchesFilter(String position, String filter) {
    if (filter == 'All') return true;
    final pos = position.toLowerCase();
    final f = filter.toLowerCase();
    if (f == 'designer') {
      return pos.contains('designer');
    } else if (f == 'developer') {
      return pos.contains('developer');
    } else if (f == 'engineering') {
      return pos.contains('engineer') ||
          pos.contains('architect') ||
          pos.contains('analyst') ||
          pos.contains('scientist');
    } else if (f == 'sales') {
      return pos.contains('sales') || pos.contains('marketing');
    } else if (f == 'management') {
      return pos.contains('manager') ||
          pos.contains('writer') ||
          pos.contains('hr');
    }
    return false;
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    return _allWorkers.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final position = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      final matchesSearch = name.contains(query) || position.contains(query);
      final matchesFilter = _matchesFilter(position, _selectedFilter);

      return matchesSearch && matchesFilter;
    }).toList();
  }

  List<Map<String, dynamic>> get _currentPageItems {
    final filtered = _filteredWorkers;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= filtered.length) return [];
    final endIndex = startIndex + _itemsPerPage;
    return filtered.sublist(
      startIndex,
      endIndex > filtered.length ? filtered.length : endIndex,
    );
  }

  int get _totalPages {
    final filtered = _filteredWorkers;
    if (filtered.isEmpty) return 1;
    return (filtered.length / _itemsPerPage).ceil();
  }

  Future<void> _deleteWorker(String docId) async {
    await FirestoreService().deleteWorker(docId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
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
                children: [
                  Text(
                    'Worker Management',
                    style: TextStyle(
                      color: textDark,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  Text(
                    'Complete all required fields to register a new worker.',
                    style: TextStyle(
                      color: textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Notification Bell & Profile Avatar
              if (widget.onProfileTap != null && widget.onLogout != null) ...[
                GestureDetector(
                  onTap: widget.onNotificationTap,
                  child: SvgPicture.asset(
                    'assets/notification_icon.svg',
                    height: 24,
                    width: 24,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF000000),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: const AssetImage(
                      'assets/profileimage.png',
                    ),
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTap: widget.onNotificationTap,
                  child: const Icon(
                    Icons.notifications_active,
                    color: Color(0xFF000000),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 24),
                CircleAvatar(
                  radius: 20,
                  backgroundImage: const AssetImage('assets/profileimage.png'),
                ),
              ],
            ],
          ),
        ),

        // List Content Area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 40.0,
              vertical: 22.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search and Add Buttons
                Row(
                  children: [
                    Expanded(
                      child: Container(
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
                                    _currentPage = 1;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search by workers name / position',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[400],
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
                    const SizedBox(width: 16),
                    _buildActionButton(
                      svgPath: 'assets/add_worker.svg',
                      label: 'Add Worker',
                      onTap: widget.onAddWorker,
                    ),
                    const SizedBox(width: 16),
                    _buildActionButton(
                      svgPath: 'assets/add_bulk_worker.svg',
                      label: 'Add Bulk Workers',
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Filter Tabs
                Container(
                  width: 550,
                  height: 50,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildFilterTab('All'),
                        _buildFilterTab('Designer'),
                        _buildFilterTab('Developer'),
                        _buildFilterTab('Engineering'),
                        _buildFilterTab('Sales'),
                        _buildFilterTab('Management'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Table Header
                if (!_isLoading && _filteredWorkers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      children: const [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Worker Name',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Work Type',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
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
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Work Type',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                        SizedBox(width: 24),
                      ],
                    ),
                  ),

                // List Items
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_filteredWorkers.isEmpty)
                  Builder(
                    builder: (context) {
                      double dynamicHeight =
                          MediaQuery.of(context).size.height - 320;
                      if (dynamicHeight < 300) dynamicHeight = 300;
                      return SizedBox(
                        width: double.infinity,
                        height: dynamicHeight,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SvgPicture.asset(
                                'assets/placeholder_workers.svg',
                                width: 120,
                                height: 100,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _allWorkers.isEmpty
                                    ? "Add workers found"
                                    : "No workers found",
                                style: const TextStyle(
                                  color: Color(0xFF0247C4),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                else
                  ..._currentPageItems.asMap().entries.map((entry) {
                    return _buildListItem(entry.value, entry.key);
                  }),

                // Pagination
                if (_filteredWorkers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _currentPage > 1
                            ? () => setState(() => _currentPage--)
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.keyboard_arrow_left,
                          size: 20,
                          color: _currentPage > 1
                              ? Colors.black
                              : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: actionBtnBlue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$_currentPage',
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _currentPage < _totalPages
                            ? () => setState(() => _currentPage++)
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.keyboard_arrow_right,
                          size: 20,
                          color: _currentPage < _totalPages
                              ? Colors.black
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListItem(Map<String, dynamic> worker, int index) {
    final name = (worker['name'] ?? '').toString();
    final email = (worker['email'] ?? '').toString();
    final type1 = (worker['type1'] ?? '').toString();
    final position = (worker['position'] ?? '').toString();
    final type2 = (worker['type2'] ?? '').toString();
    final docId = worker['id'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: AssetImage(
                    index % 2 == 0
                        ? 'assets/profileimage.png'
                        : 'assets/boy.png',
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    Text(
                      email,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              type1,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              position,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              type2,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8.0),
            child: PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert, size: 24),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              color: Color(0xFFFFFFFF),
              elevation: 8,
              offset: const Offset(0, 40),
              onSelected: (value) {
                if (value == 'preview') {
                  showDialog(
                    context: context,
                    barrierColor: const Color(
                      0xFF0247C4,
                    ).withValues(alpha: 0.5),
                    builder: (context) => WorkerProfilePreviewDialog(
                      name: name,
                      email: email,
                      position: position,
                      workType: type1,
                      attendanceType: type2,
                    ),
                  );
                } else if (value == 'edit') {
                  widget.onEditWorker?.call(worker);
                } else if (value == 'delete') {
                  _deleteWorker(docId);
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'preview',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.remove_red_eye,
                        size: 16,
                        color: Color(0xFF000000),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Preview',
                        style: TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 16, color: actionBtnBlue),
                      const SizedBox(width: 8),
                      Text(
                        'Edit Worker',
                        style: TextStyle(
                          color: actionBtnBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.delete, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
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
    );
  }

  Widget _buildActionButton({
    required String svgPath,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: buttonColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SvgPicture.asset(
                  svgPath,
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFFFFFFF),
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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

  Widget _buildFilterTab(String label) {
    final bool isActive = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
          _currentPage = 1;
        });
      },
      child: Container(
        height: 38,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? buttonColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Color(0xFFFFFFFF) : Colors.black,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ADD NEW WORKER FLOW (EXPERIENCE & DOCS)
// ==========================================
class AddNewWorkerFlow extends StatefulWidget {
  final VoidCallback? onBack;
  final Map<String, dynamic>? workerToEdit;

  const AddNewWorkerFlow({super.key, this.onBack, this.workerToEdit});

  @override
  State<AddNewWorkerFlow> createState() => _AddNewWorkerFlowState();
}

class _AddNewWorkerFlowState extends State<AddNewWorkerFlow> {
  int _activeTabIndex = 0;
  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _religionController = TextEditingController();
  final _dobController = TextEditingController();
  final _genderController = TextEditingController();
  final _addressController = TextEditingController();
  final _positionController = TextEditingController();
  final _type1Controller = TextEditingController();
  final _type2Controller = TextEditingController();

  // Upload states
  Uint8List? _profileImageBytes;
  String? _profileImageName;
  String? _existingProfileImageUrl;

  Uint8List? _frontIdBytes;
  String? _frontIdName;
  String? _existingFrontIdUrl;

  Uint8List? _backIdBytes;
  String? _backIdName;
  String? _existingBackIdUrl;

  Uint8List? _cvBytes;
  String? _cvName;
  String? _existingCvUrl;
  bool _isCvUploaded = false;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.workerToEdit != null) {
      _nameController.text = (widget.workerToEdit!['name'] ?? '').toString();
      _fatherNameController.text = (widget.workerToEdit!['fatherName'] ?? '')
          .toString();
      _emailController.text = (widget.workerToEdit!['email'] ?? '').toString();
      _phoneController.text = (widget.workerToEdit!['phone'] ?? '').toString();
      _nationalIdController.text = (widget.workerToEdit!['nationalId'] ?? '')
          .toString();
      _religionController.text = (widget.workerToEdit!['religion'] ?? '')
          .toString();
      _dobController.text = (widget.workerToEdit!['dob'] ?? '').toString();
      _genderController.text = (widget.workerToEdit!['gender'] ?? '')
          .toString();
      _addressController.text = (widget.workerToEdit!['address'] ?? '')
          .toString();
      _positionController.text = (widget.workerToEdit!['position'] ?? '')
          .toString();
      _type1Controller.text = (widget.workerToEdit!['type1'] ?? '').toString();
      _type2Controller.text = (widget.workerToEdit!['type2'] ?? '').toString();

      _existingProfileImageUrl = widget.workerToEdit!['profileImage']?.toString();
      _existingFrontIdUrl = widget.workerToEdit!['frontId']?.toString();
      _existingBackIdUrl = widget.workerToEdit!['backId']?.toString();
      _existingCvUrl = widget.workerToEdit!['cv']?.toString();
      if (_existingCvUrl != null && _existingCvUrl!.isNotEmpty) {
        _isCvUploaded = true;
        _cvName = _existingCvUrl!.split('/').last;
      }
    }
  }

  Future<String?> _uploadToStorage(String folder, String fileName, Uint8List fileBytes) async {
    try {
      final ref = FirebaseStorage.instance.ref().child('hrms_documents/$folder/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = ref.putData(fileBytes);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Firebase Storage upload failed: $e');
      return null;
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _profileImageBytes = bytes;
          _profileImageName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking profile image: $e');
    }
  }

  Future<void> _pickFrontId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _frontIdBytes = bytes;
          _frontIdName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking front ID: $e');
    }
  }

  Future<void> _pickBackId() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _backIdBytes = bytes;
          _backIdName = file.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking back ID: $e');
    }
  }

  Future<void> _pickCv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = io.File(file.path!).readAsBytesSync();
        }
        setState(() {
          _cvBytes = bytes;
          _cvName = file.name;
          _isCvUploaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error picking CV: $e');
    }
  }

  Future<void> _saveWorker() async {
    setState(() {
      _isSaving = true;
    });

    String? profileImageUrl = _existingProfileImageUrl;
    String? frontIdUrl = _existingFrontIdUrl;
    String? backIdUrl = _existingBackIdUrl;
    String? cvUrl = _existingCvUrl;

    if (_profileImageBytes != null) {
      profileImageUrl = await _uploadToStorage('profile_images', _profileImageName ?? 'profile.jpg', _profileImageBytes!);
      profileImageUrl ??= 'mock://profile_images/$_profileImageName';
    }

    if (_frontIdBytes != null) {
      frontIdUrl = await _uploadToStorage('id_cards', _frontIdName ?? 'front.jpg', _frontIdBytes!);
      frontIdUrl ??= 'mock://id_cards/$_frontIdName';
    }

    if (_backIdBytes != null) {
      backIdUrl = await _uploadToStorage('id_cards', _backIdName ?? 'back.jpg', _backIdBytes!);
      backIdUrl ??= 'mock://id_cards/$_backIdName';
    }

    if (_cvBytes != null) {
      cvUrl = await _uploadToStorage('cvs', _cvName ?? 'cv.pdf', _cvBytes!);
      cvUrl ??= 'mock://cvs/$_cvName';
    }

    final data = {
      'name': _nameController.text.isNotEmpty
          ? _nameController.text
          : 'New Worker',
      'fatherName': _fatherNameController.text,
      'email': _emailController.text.isNotEmpty
          ? _emailController.text
          : 'worker@email.com',
      'phone': _phoneController.text,
      'nationalId': _nationalIdController.text,
      'religion': _religionController.text,
      'dob': _dobController.text,
      'gender': _genderController.text,
      'address': _addressController.text,
      'type1': _type1Controller.text.isNotEmpty
          ? _type1Controller.text
          : 'Full-Time',
      'position': _positionController.text.isNotEmpty
          ? _positionController.text
          : 'Employee',
      'type2': _type2Controller.text.isNotEmpty
          ? _type2Controller.text
          : 'On-Site',
      'profileImage': profileImageUrl,
      'frontId': frontIdUrl,
      'backId': backIdUrl,
      'cv': cvUrl,
    };

    try {
      if (widget.workerToEdit != null) {
        await FirestoreService().updateWorker(widget.workerToEdit!['id'], data);
      } else {
        await FirestoreService().addWorker(data);
      }
    } catch (e) {
      debugPrint('Error saving worker: $e');
    }

    setState(() {
      _isSaving = false;
    });

    if (mounted) {
      widget.onBack?.call();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _religionController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _addressController.dispose();
    _positionController.dispose();
    _type1Controller.dispose();
    _type2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FA), // Dashboard background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Area
          Container(
            height: 94,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(
                bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => widget.onBack?.call(),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Add New Worker',
                          style: TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Fill in the worker details to get started.',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Save Button (Blue state based on image 2)
                GestureDetector(
                  onTap: _isSaving ? null : _saveWorker,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: _isSaving ? Colors.grey : const Color(0xFF0B50C3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs and Form Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tabs Section
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildTopTab('Worker Detail', 0)),
                        Expanded(child: _buildTopTab('Experience', 1)),
                        Expanded(child: _buildTopTab('Documentation', 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Switch Content based on active tab
                  if (_activeTabIndex == 0)
                    WorkerDetailFormSection(
                      nameController: _nameController,
                      fatherNameController: _fatherNameController,
                      emailController: _emailController,
                      phoneController: _phoneController,
                      nationalIdController: _nationalIdController,
                      religionController: _religionController,
                      dobController: _dobController,
                      genderController: _genderController,
                      addressController: _addressController,
                      profileImageBytes: _profileImageBytes,
                      profileImageName: _profileImageName,
                      existingProfileImageUrl: _existingProfileImageUrl,
                      onUploadProfileTap: _pickProfileImage,
                      onNextStep: () => setState(() => _activeTabIndex = 1),
                    ),
                  if (_activeTabIndex == 1)
                    ExperienceFormSection(
                      positionController: _positionController,
                      type1Controller: _type1Controller,
                      type2Controller: _type2Controller,
                      onNextStep: () => setState(() => _activeTabIndex = 2),
                    ),
                  if (_activeTabIndex == 2)
                    DocumentationSection(
                      frontIdBytes: _frontIdBytes,
                      frontIdName: _frontIdName,
                      existingFrontIdUrl: _existingFrontIdUrl,
                      onUploadFrontTap: _pickFrontId,
                      backIdBytes: _backIdBytes,
                      backIdName: _backIdName,
                      existingBackIdUrl: _existingBackIdUrl,
                      onUploadBackTap: _pickBackId,
                      cvBytes: _cvBytes,
                      cvName: _cvName,
                      existingCvUrl: _existingCvUrl,
                      isCvUploaded: _isCvUploaded,
                      onUploadCvTap: _pickCv,
                      onDeleteCvTap: () {
                        setState(() {
                          _cvBytes = null;
                          _cvName = null;
                          _existingCvUrl = null;
                          _isCvUploaded = false;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTab(String title, int index) {
    bool isActive = _activeTabIndex == index;
    BorderRadiusGeometry? borderRadius;
    if (isActive) {
      if (index == 0) {
        borderRadius = const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        );
      } else if (index == 2) {
        borderRadius = const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        );
      }
    }
    return GestureDetector(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8EEF9) : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }
}

// ==========================================
// WORKER DETAIL FORM SECTION
// ==========================================
class WorkerDetailFormSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController fatherNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController nationalIdController;
  final TextEditingController religionController;
  final TextEditingController dobController;
  final TextEditingController genderController;
  final TextEditingController addressController;
  final VoidCallback? onNextStep;
  final Uint8List? profileImageBytes;
  final String? profileImageName;
  final String? existingProfileImageUrl;
  final VoidCallback? onUploadProfileTap;

  const WorkerDetailFormSection({
    super.key,
    required this.nameController,
    required this.fatherNameController,
    required this.emailController,
    required this.phoneController,
    required this.nationalIdController,
    required this.religionController,
    required this.dobController,
    required this.genderController,
    required this.addressController,
    this.onNextStep,
    this.profileImageBytes,
    this.profileImageName,
    this.existingProfileImageUrl,
    this.onUploadProfileTap,
  });

  final Color formBgGrey = const Color(0xFFF3F5F8);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: onNextStep,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Next Step',
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === LEFT: Input Form Area ===
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Worker Name:',
                            'Enter your name',
                            controller: nameController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Worker Father/Husband Name:',
                            'Enter your name',
                            controller: fatherNameController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Worker E-mail:',
                            'Enter your email',
                            controller: emailController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Contact no:',
                            '0000000000',
                            controller: phoneController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'National ID:',
                            'Enter your national id',
                            controller: nationalIdController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Professed Religion:',
                            'Enter your religion',
                            controller: religionController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Worker Date of Birth:',
                            '00/00/0000',
                            suffixIcon: Icons.calendar_month,
                            controller: dobController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Gender:',
                            'Male',
                            isDropdown: true,
                            controller: genderController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInputField(
                      'Worker Address:',
                      'Enter your address',
                      isTextArea: true,
                      controller: addressController,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

            // === RIGHT: Profile Upload & Status ===
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Upload Section
                  const Text(
                    'Worker Profile',
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onUploadProfileTap,
                    child: Container(
                      height: 280,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF000000).withValues(alpha: 0.01),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: profileImageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  profileImageBytes!,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    color: Colors.black54,
                                    child: Text(
                                      profileImageName ?? 'Profile Image',
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.edit, color: Colors.white, size: 16),
                                  ),
                                ),
                              ],
                            )
                          : existingProfileImageUrl != null && existingProfileImageUrl!.startsWith('http')
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      existingProfileImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => _buildUploadPlaceholder(),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(Icons.edit, color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ],
                                )
                              : _buildUploadPlaceholder(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Relationship Status Section
                  const Text(
                    'Relationship Status:',
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildCustomRadio(label: 'Married', isSelected: true),
                      const SizedBox(width: 40),
                      _buildCustomRadio(label: 'Single', isSelected: false),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/Upload_profile.svg',
          height: 64,
          width: 64,
        ),
        const SizedBox(height: 12),
        const Text(
          'Upload Profile',
          style: TextStyle(
            color: Color(0xFF000000),
            fontWeight: FontWeight.w700,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap to upload a profile image\nPNG or JPG',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }
}

// ==========================================
// EXPERIENCE SECTION (IMAGE 1 + CUSTOM LEAVE)
// ==========================================
class ExperienceFormSection extends StatelessWidget {
  final TextEditingController positionController;
  final TextEditingController type1Controller;
  final TextEditingController type2Controller;
  final VoidCallback? onNextStep;

  const ExperienceFormSection({
    super.key,
    required this.positionController,
    required this.type1Controller,
    required this.type2Controller,
    this.onNextStep,
  });

  final Color formBgGrey = const Color(0xFFF3F5F8);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Job Experience Information',
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: onNextStep,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Next Step',
                      style: TextStyle(
                        color: Color(0xFF000000),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Color(0xFF000000),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Main Grid & Right Panel (Calendar)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Form
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Job Position:',
                            'Enter your level',
                            controller: positionController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Experience Level:',
                            'Enter your level',
                            isDropdown: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Work Type:',
                            'Enter your work type',
                            isDropdown: true,
                            controller: type1Controller,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildInputField(
                            'Education:',
                            'Enter your education',
                            isDropdown: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInputField(
                            'Attendance Type:',
                            'Enter your attendance type',
                            isDropdown: true,
                            controller: type2Controller,
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(
                          child: SizedBox(),
                        ), // Empty space to match image
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Right Calendar
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Joining Date set',
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Icon(Icons.keyboard_arrow_left, size: 20),
                            Text(
                              'JANUARY20XX',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_right, size: 20),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildDayPill('SUN', true),
                            _buildDayPill('MON', false),
                            _buildDayPill('THE', false),
                            _buildDayPill('WED', false),
                            _buildDayPill('THU', false),
                            _buildDayPill('FRI', false, isGreen: true),
                            _buildDayPill('SAT', false),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Calendar Grid Mockup
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(31, (index) {
                            int day = index + 1;
                            bool isSelected = day == 9;
                            return Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0B50C3)
                                    : Color(0xFFFFFFFF),
                                border: isSelected
                                    ? null
                                    : Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? Color(0xFFFFFFFF)
                                      : Colors.black,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B50C3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Set',
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
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
          ],
        ),
        const SizedBox(height: 40),

        // Salary Section
        const Text(
          'Salary Section',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: formBgGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Salary Type:',
                      'Enter your salary type',
                      isDropdown: true,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'Currency:',
                      'Enter your currency',
                      isDropdown: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Salary Amount:',
                      'Enter your amount',
                    ),
                  ),
                  const SizedBox(width: 24),
                  const Expanded(child: SizedBox()), // empty
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Custom Leave Section (As Requested by user)
        const Text(
          'Leave Section',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: formBgGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      'Leave Policy:',
                      'Select policy',
                      isDropdown: true,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField(
                      'Annual Leaves (Days):',
                      'e.g., 14',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildInputField('Sick Leaves (Days):', 'e.g., 7'),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildInputField('Casual Leaves (Days):', 'e.g., 3'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildDayPill(String text, bool isRed, {bool isGreen = false}) {
    Color bg = isRed
        ? Colors.red
        : (isGreen ? Colors.green : const Color(0xFF0B50C3));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.bold,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }
}

// ==========================================
// DOCUMENTATION SECTION (IMAGE 2)
// ==========================================
class DocumentationSection extends StatelessWidget {
  final Uint8List? frontIdBytes;
  final String? frontIdName;
  final String? existingFrontIdUrl;
  final VoidCallback? onUploadFrontTap;

  final Uint8List? backIdBytes;
  final String? backIdName;
  final String? existingBackIdUrl;
  final VoidCallback? onUploadBackTap;

  final Uint8List? cvBytes;
  final String? cvName;
  final String? existingCvUrl;
  final bool isCvUploaded;
  final VoidCallback? onUploadCvTap;
  final VoidCallback? onDeleteCvTap;

  const DocumentationSection({
    super.key,
    this.frontIdBytes,
    this.frontIdName,
    this.existingFrontIdUrl,
    this.onUploadFrontTap,
    this.backIdBytes,
    this.backIdName,
    this.existingBackIdUrl,
    this.onUploadBackTap,
    this.cvBytes,
    this.cvName,
    this.existingCvUrl,
    this.isCvUploaded = false,
    this.onUploadCvTap,
    this.onDeleteCvTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Documentation',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Side: ID Card Upload
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ID Card:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F5F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload Front Side:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildIdUploadBox(
                          label: 'Upload front side ID Card',
                          bytes: frontIdBytes,
                          fileName: frontIdName,
                          existingUrl: existingFrontIdUrl,
                          onTap: onUploadFrontTap,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Upload Back Side:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildIdUploadBox(
                          label: 'Upload back side ID Card',
                          bytes: backIdBytes,
                          fileName: backIdName,
                          existingUrl: existingBackIdUrl,
                          onTap: onUploadBackTap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 32),
            // Right Side: CV Upload Preview
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload CV:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  isCvUploaded ? _buildCvPreview() : _buildCvUpload(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdUploadBox({
    required String label,
    Uint8List? bytes,
    String? fileName,
    String? existingUrl,
    VoidCallback? onTap,
  }) {
    final bool hasFile = bytes != null || (existingUrl != null && existingUrl.isNotEmpty);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 200,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasFile ? const Color(0xFF0B50C3).withValues(alpha: 0.5) : Colors.grey.shade200,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: hasFile
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(bytes, fit: BoxFit.cover)
                  else if (existingUrl != null && existingUrl.startsWith('http'))
                    Image.network(
                      existingUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildIdPlaceholder(label, hasFile),
                    )
                  else
                    _buildIdPlaceholder(label, hasFile),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black54,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              fileName ?? 'File uploaded',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, color: Colors.white70, size: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildIdPlaceholder(label, false),
      ),
    );
  }

  Widget _buildIdPlaceholder(String label, bool hasFile) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.badge,
          size: 48,
          color: hasFile ? const Color(0xFF0B50C3) : Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to select file',
          style: TextStyle(
            color: Colors.grey.shade300,
            fontSize: 12,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  Widget _buildCvUpload() {
    return _buildCvContainer(
      overlay: GestureDetector(
        onTap: onUploadCvTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Upload',
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/Upload_profile.svg',
                height: 18,
                width: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCvPreview() {
    return _buildCvContainer(
      overlay: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cvName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B50C3).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        cvName!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onUploadCvTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Edit',
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset('assets/edit_icon.svg', height: 18, width: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: onDeleteCvTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Delete',
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        'assets/delete_icon.svg',
                        height: 18,
                        width: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCvContainer({required Widget overlay}) {
    return Container(
      height: 580,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(height: 16, width: 200, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Container(height: 10, width: 150, color: Colors.grey.shade300),
                const SizedBox(height: 40),
                ...List.generate(
                  8,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(color: const Color(0xFFFFFFFF).withValues(alpha: 0.5)),
          overlay,
        ],
      ),
    );
  }
}

// ==========================================
// FILE-LEVEL SHARED HELPERS
// ==========================================
Widget _buildInputField(
  String label,
  String hint, {
  IconData? suffixIcon,
  bool isDropdown = false,
  bool isTextArea = false,
  TextEditingController? controller,
}) {
  final isAmount = label.toLowerCase().contains('amount');
  final isLeaves = label.toLowerCase().contains('leaves');
  final isNumeric = isAmount || isLeaves;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'SF Pro Display',
        ),
      ),
      const SizedBox(height: 8),
      Container(
        height: isTextArea ? 90 : 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: isTextArea ? Alignment.topLeft : Alignment.center,
        child: TextField(
          maxLines: isTextArea ? 4 : 1,
          controller: controller,
          keyboardType: isNumeric
              ? (isAmount
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number)
              : null,
          inputFormatters: isNumeric
              ? [
                  FilteringTextInputFormatter.allow(
                    isAmount ? RegExp(r'^\d*\.?\d*') : RegExp(r'^\d*'),
                  ),
                ]
              : null,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: isTextArea
                ? const EdgeInsets.only(top: 14)
                : EdgeInsets.zero,
            suffixIcon: isDropdown
                ? Icon(
                    Icons.arrow_drop_down,
                    color: Colors.grey.shade400,
                    size: 22,
                  )
                : (suffixIcon != null
                      ? Icon(suffixIcon, color: Colors.grey.shade400, size: 22)
                      : null),
          ),
        ),
      ),
    ],
  );
}

Widget _buildCustomRadio({required String label, required bool isSelected}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Color(0xFF000000), width: 2),
        ),
        child: isSelected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF000000),
                  ),
                ),
              )
            : const SizedBox(),
      ),
      const SizedBox(width: 10),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 16,
          fontWeight: FontWeight.w500,
          fontFamily: 'SF Pro Display',
        ),
      ),
    ],
  );
}

// ==========================================
// WORKER PROFILE PREVIEW DIALOG (POPUP)
// ==========================================
class WorkerProfilePreviewDialog extends StatelessWidget {
  final String name;
  final String email;
  final String position;
  final String workType;
  final String attendanceType;

  const WorkerProfilePreviewDialog({
    super.key,
    required this.name,
    required this.email,
    required this.position,
    required this.workType,
    required this.attendanceType,
  });

  // Exact colors picked from the image
  final Color primaryBlue = const Color(0xFF0953D4); // The main vibrant blue
  final Color titleBarBlue = const Color(
    0xFF0B58E6,
  ); // Slightly lighter top bar
  final Color iconLightBlue = const Color(0xFFE5EEFC); // Card icon background
  final Color cardBorderGrey = const Color(0xFFE8E8E8); // Subtle card border
  final Color textBlack = const Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 480,
          height: 568,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF000000).withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // ==========================================
              // TOP HEADER SECTION (BLUE)
              // ==========================================
              Container(
                decoration: BoxDecoration(color: primaryBlue),
                child: Column(
                  children: [
                    // --- Title Bar ---
                    Container(
                      height: 56,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white30, width: 1),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 40), // Spacer for centering
                          const Text(
                            'Worker Profile Preview',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFFFFFFFF),
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),

                    // --- Profile Details Area ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar with White Border
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFFFFF),
                                width: 2.0,
                              ),
                              image: const DecorationImage(
                                image: AssetImage('assets/boy.png'),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Name, Badge, and Contact Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // "Active" Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.circle,
                                        color: Color(0xFF00FF00),
                                        size: 10,
                                      ), // Bright green dot
                                      const SizedBox(width: 6),
                                      Text(
                                        'Active',
                                        style: TextStyle(
                                          color: primaryBlue,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Email Row
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.mail_outline,
                                      color: Color(0xFFFFFFFF),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        email,
                                        style: const TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),

                                // Phone Row
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.phone,
                                      color: Color(0xFFFFFFFF),
                                      size: 20,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      '123 5434567',
                                      style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
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
                ),
              ),

              // ==========================================
              // BOTTOM GRID SECTION (WHITE)
              // ==========================================
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Row 1
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              Icons.person,
                              'Father/Husband Name',
                              'Ahmad',
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Exact spelling from image ("Postion")
                          Expanded(
                            child: _buildInfoCard(
                              Icons.business_center,
                              'Postion',
                              position,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Row 2
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              Icons.location_city,
                              'Attendance Type',
                              attendanceType,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              Icons.schedule,
                              'Work Type',
                              workType,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Row 3
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              Icons.show_chart,
                              'Experience Level',
                              'Junior Level',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              Icons.calendar_month,
                              'Joining Date',
                              '10/10/2025',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Row 4
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              Icons.transgender,
                              'Gender',
                              'Male',
                            ),
                          ), // Closest to combined symbol
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              Icons.volunteer_activism,
                              'Salary',
                              'Rs 12,000',
                            ),
                          ), // Hand holding icon
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widget for the Cards ---
  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      height: 70, // Reduced from 90 to match 568px dialog height
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorderGrey, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon Box
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconLightBlue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: Icon(icon, color: primaryBlue, size: 20)),
          ),
          const SizedBox(width: 12),

          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.w600, // Semi-bold for the label
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.bold, // Bold for the value
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
