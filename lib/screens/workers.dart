import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/preferences_service.dart';
import '../utils/premium_gate.dart';
import 'pricing_screen.dart';
import 'add_worker_flow.dart';
import 'add_bulk_worker_screen.dart';
import '../utils/delete_dialog.dart';
import '../utils/image_utils.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';

void main() {
  runApp(const WorkerManagementApp());
}

class WorkerManagementApp extends StatelessWidget {
  const WorkerManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worker Management'.tr(),
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

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  // 0: Dashboard List, 1: Add Worker Form
  int _currentMenuIndex = 1;
  bool _isPremium = false;

  final Color sidebarBlue = const Color(0xFF0B50C3);
  final Color activeTabBlue = const Color(0xFF4C84E0);

  @override
  void initState() {
    super.initState();
    _loadPremiumStatus();
  }

  Future<void> _loadPremiumStatus() async {
    bool isPremium = false;
    final user = AuthService().currentUser;
    // Always read premium status from Firestore, never trust local cache.
    if (user != null && !user.isAnonymous) {
      try {
        final profile = await FirestoreService().getUserProfile();
        isPremium = profile?['isPremium'] == true;
        await PreferencesService.setPremium(isPremium);
      } catch (_) {
        isPremium = await PreferencesService.isPremium();
      }
    }
    if (mounted) setState(() => _isPremium = isPremium);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 270,
            color: sidebarBlue,
            child: Column(
              children: [
                if (!(AuthService().currentUser?.isAnonymous ?? false) &&
                    !_isPremium)
                  GestureDetector(
                    onTap: () async {
                      final result = await showDialog<bool>(
                        context: context,
                        barrierColor: const Color(
                          0xFF0247C4,
                        ).withValues(alpha: 0.5),
                        builder: (context) => const SubscriptionDialog(),
                      );
                      if (result == true) {
                        await _loadPremiumStatus();
                      }
                    },
                    child: Container(
                      width: 238,
                      margin: const EdgeInsets.only(
                        top: 29,
                        left: 16,
                        right: 16,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
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
                              Text(
                                'upgrade_pro'.tr(),
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
                          _buildCheckItem('unlock_all_features'.tr()),
                          _buildCheckItem('no_commitment'.tr()),
                          _buildCheckItem('cancel_anytime'.tr()),
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'get_to_pro'.tr(),
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro',
                                        height: 1.1,
                                      ),
                                    ),
                                    Text(
                                      'subscribe_now'.tr(),
                                      maxLines: 1,
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
                                right: -5,
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
                  'sidebar_dashboard'.tr(),
                  _currentMenuIndex == 0,
                  onTap: () => setState(() => _currentMenuIndex = 0),
                ),
                _buildNavItem(
                  Icons.people_alt,
                  'sidebar_workers'.tr(),
                  _currentMenuIndex == 1,
                  onTap: () => setState(() => _currentMenuIndex = 1),
                ),
                _buildNavItem(
                  Icons.engineering,
                  'sidebar_workforce'.tr(),
                  false,
                  hasDropdown: true,
                ),
                _buildNavItem(
                  Icons.receipt_long,
                  'sidebar_expenses'.tr(),
                  false,
                ),
                _buildNavItem(Icons.settings, 'sidebar_settings'.tr(), false),
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
                  onAddBulkWorker: () => setState(() => _currentMenuIndex = 2),
                ), // Index 0
                AddNewWorkerFlow(
                  onBack: () => setState(() => _currentMenuIndex = 0),
                ), // Index 1
                AddBulkWorkerScreen(
                  onBack: () => setState(() => _currentMenuIndex = 0),
                ), // Index 2
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
              borderRadius: BorderRadius.circular(6),
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
  bool _isAddingBulkWorker = false;
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
    } else if (_isAddingBulkWorker) {
      return AddBulkWorkerScreen(
        onBack: () {
          setState(() {
            _isAddingBulkWorker = false;
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
        onAddBulkWorker: () {
          setState(() {
            _isAddingBulkWorker = true;
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

class DashboardWorkerList extends StatefulWidget {
  final VoidCallback onAddWorker;
  final VoidCallback? onAddBulkWorker;
  final ValueChanged<Map<String, dynamic>>? onEditWorker;
  final VoidCallback? onLogout;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;

  const DashboardWorkerList({
    super.key,
    required this.onAddWorker,
    this.onAddBulkWorker,
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
  static const int _itemsPerPage = 8;
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
              _allWorkers = sortedList;
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
      return pos.contains('designer') ||
          pos.contains('design lead') ||
          pos.contains('creative director') ||
          pos.contains('ui') ||
          pos.contains('ux') ||
          pos.contains('graphic') ||
          pos.contains('visual');
    } else if (f == 'developer') {
      return pos.contains('developer') ||
          pos.contains('programmer') ||
          pos.contains('coder') ||
          pos.contains('software') ||
          pos.contains('frontend') ||
          pos.contains('backend') ||
          pos.contains('full stack') ||
          pos.contains('fullstack');
    } else if (f == 'engineering') {
      return pos.contains('engineer') ||
          pos.contains('architect') ||
          pos.contains('devops') ||
          pos.contains('cloud') ||
          pos.contains('data') ||
          pos.contains('scientist') ||
          pos.contains('machine learning') ||
          pos.contains('ml') ||
          pos.contains('qa') ||
          pos.contains('tester') ||
          pos.contains('it support') ||
          pos.contains('network') ||
          pos.contains('database') ||
          pos.contains('dba') ||
          pos.contains('cyber') ||
          pos.contains('security') ||
          pos.contains('cto') ||
          pos.contains('chief technology');
    } else if (f == 'sales') {
      return pos.contains('sales') ||
          pos.contains('marketing') ||
          pos.contains('seo') ||
          pos.contains('content') ||
          pos.contains('social media') ||
          pos.contains('brand') ||
          pos.contains('business development') ||
          pos.contains('account executive') ||
          pos.contains('customer success');
    } else if (f == 'management') {
      return pos.contains('manager') ||
          pos.contains('director') ||
          pos.contains('head') ||
          pos.contains('lead') ||
          pos.contains('chief') ||
          pos.contains('cpo') ||
          pos.contains('product') ||
          pos.contains('project') ||
          pos.contains('program') ||
          pos.contains('scrum') ||
          pos.contains('agile') ||
          pos.contains('business analyst');
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
    final total = _totalPages;
    if (_currentPage > total) {
      _currentPage = total;
    }
    if (_currentPage < 1) {
      _currentPage = 1;
    }
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
    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_worker'.tr(),
      content: 'delete_worker_desc'.tr(),
    );
    if (!confirmed) return;

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    try {
      if (isGuest) {
        DummyData.workers.removeWhere((w) => w['id']?.toString() == docId);
        await DummyData.saveToPrefs();
        setState(() {
          _allWorkers = DummyData.workers;
        });
      } else {
        await FirestoreService().deleteWorker(docId);
      }
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'worker_deleted_successfully'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_delete_record'.tr(
            namedArgs: {'error': e.toString()},
          ),
          isError: true,
        );
      }
    }
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
                    'worker_management'.tr(),
                    style: TextStyle(
                      color: textDark,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  Text(
                    'complete_required_fields_worker'.tr(),
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
              if (widget.onProfileTap != null && widget.onLogout != null) ...[
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
                const UserAvatar(),
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
                        height: 48,
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
                                  hintText: 'search_workers_name_position'.tr(),
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
                    const SizedBox(width: 10),
                    _buildActionButton(
                      svgPath: 'assets/add_worker.svg',
                      label: 'add_worker'.tr(),
                      onTap: () async {
                        final isPremium = await PreferencesService.isPremium();
                        if (!mounted) return;
                        final isGuest =
                            AuthService().currentUser?.isAnonymous ?? false;
                        if (!PremiumGate.canAddEntry(
                          currentEntryCount: _allWorkers.length,
                          isPremium: isPremium,
                          isGuest: isGuest,
                        )) {
                          if (!mounted) return;
                          final upgraded =
                              await PremiumGate.shouldShowUpgradeDialog(
                                context,
                              );
                          if (upgraded == true && mounted) {
                            widget.onAddWorker();
                          }
                          return;
                        }
                        widget.onAddWorker();
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildActionButton(
                      svgPath: 'assets/add_bulk_worker.svg',
                      label: 'add_bulk_workers'.tr(),
                      onTap: () async {
                        final isPremium = await PreferencesService.isPremium();
                        if (!mounted) return;
                        final isGuest =
                            AuthService().currentUser?.isAnonymous ?? false;
                        if (!PremiumGate.canAddEntry(
                          currentEntryCount: _allWorkers.length,
                          isPremium: isPremium,
                          isGuest: isGuest,
                        )) {
                          if (!mounted) return;
                          final upgraded =
                              await PremiumGate.shouldShowUpgradeDialog(
                                context,
                              );
                          if (upgraded == true && mounted) {
                            (widget.onAddBulkWorker ?? () {})();
                          }
                          return;
                        }
                        (widget.onAddBulkWorker ?? () {})();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Filter Tabs
                Container(
                  width: 480,
                  height: 50,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildFilterTab('All', 'all_filter'.tr()),
                        _buildFilterTab('Designer', 'designer'.tr()),
                        _buildFilterTab('Developer', 'developer'.tr()),
                        _buildFilterTab('Engineering', 'engineering'.tr()),
                        _buildFilterTab('Sales', 'sales'.tr()),
                        _buildFilterTab('Management', 'management'.tr()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Unified Table Layout or Loading/Empty states
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
                                    ? 'add_workers_found'.tr()
                                    : 'no_workers_found'.tr(),
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
                  _buildTable(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final double tableHeight = (MediaQuery.of(context).size.height - 279).clamp(
      495.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Table Headers
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'worker_name'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        fontFamily: 'SF Pro Display',
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'work_type'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        fontFamily: 'SF Pro Display',
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'position'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        fontFamily: 'SF Pro Display',
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'attendance_type'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          // List Items
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _currentPageItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildListItem(_currentPageItems[index], index);
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
                    borderRadius: BorderRadius.circular(6),
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
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> worker, int index) {
    final name = (worker['name'] ?? '').toString();
    final email = (worker['email'] ?? '').toString();
    final type1 = (worker['type1'] ?? '').toString();
    final position = (worker['position'] ?? '').toString();
    final type2 = (worker['type2'] ?? '').toString();
    final profileImage = worker['profileImage'] as String?;
    final docId = (worker['id'] ?? '').toString();

    final localizedType1 = LocalizationHelper.localizeType1(type1);
    final localizedType2 = LocalizationHelper.localizeType2(type2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      profileImage,
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
                            maxLines: 2,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
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
              child: Text(
                localizedType1,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Tooltip(
                message: position,
                child: Text(
                  position,
                  maxLines: 2,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              localizedType2,
              maxLines: 1,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: PopupMenuButton<String>(
              tooltip: 'actions'.tr(),
              icon: const Icon(Icons.more_vert, size: 24),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFFCBCBCB)),
              ),
              color: const Color(0xFFFBFBFC),
              elevation: 8,
              offset: const Offset(0, 40),
              onSelected: (value) {
                if (value == 'preview') {
                  final phone = (worker['phone'] ?? '').toString();
                  final fatherName = (worker['fatherName'] ?? '').toString();
                  final joiningDate = (worker['joiningDate'] ?? '').toString();
                  final gender = (worker['gender'] ?? '').toString();
                  final currency = (worker['currency'] ?? '').toString();
                  final salaryAmount = (worker['salaryAmount'] ?? '')
                      .toString();
                  final salary = (salaryAmount.isNotEmpty)
                      ? (currency.isNotEmpty
                            ? '$currency $salaryAmount'
                            : salaryAmount)
                      : '';

                  showDialog(
                    context: context,
                    barrierColor: const Color(
                      0xFF0247C4,
                    ).withValues(alpha: 0.5),
                    builder: (context) => WorkerProfilePreviewDialog(
                      name: name,
                      email: email,
                      position: position,
                      workType: localizedType1,
                      attendanceType: localizedType2,
                      fatherName: fatherName,
                      phone: phone,
                      joiningDate: joiningDate,
                      gender: gender,
                      salary: salary,
                      experienceLevel: (worker['experienceLevel'] ?? '')
                          .toString(),
                      profileImage: profileImage,
                    ),
                  );
                } else if (value == 'edit') {
                  widget.onEditWorker?.call(worker);
                } else if (value == 'delete') {
                  _deleteWorker(docId);
                }
              },
              constraints: const BoxConstraints(maxWidth: 168),
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'preview',
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.remove_red_eye,
                        size: 16,
                        color: Color(0xFF000000),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'preview'.tr(),
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
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 16, color: actionBtnBlue),
                      const SizedBox(width: 8),
                      Text(
                        'edit_worker'.tr(),
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
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(width: 8),
                      Text(
                        'delete'.tr(),
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
      height: 48,
      decoration: BoxDecoration(
        color: buttonColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
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

  Widget _buildFilterTab(String filterKey, String displayLabel) {
    final bool isActive = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filterKey;
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
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
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
// WORKER PROFILE PREVIEW DIALOG (POPUP)
// ==========================================
class WorkerProfilePreviewDialog extends StatelessWidget {
  final String name;
  final String email;
  final String position;
  final String workType;
  final String attendanceType;
  final String fatherName;
  final String phone;
  final String joiningDate;
  final String gender;
  final String salary;
  final String experienceLevel;
  final String? profileImage;
  const WorkerProfilePreviewDialog({
    super.key,
    required this.name,
    required this.email,
    required this.position,
    required this.workType,
    required this.attendanceType,
    required this.fatherName,
    required this.phone,
    required this.joiningDate,
    required this.gender,
    required this.salary,
    required this.experienceLevel,
    this.profileImage,
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
          height: 580,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
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
                decoration: const BoxDecoration(color: Color(0xFF0247C4)),
                child: Column(
                  children: [
                    // --- Title Bar ---
                    Container(
                      height: 44,
                      decoration: const BoxDecoration(color: Color(0xFF004FDE)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 40), // Spacer for centering
                          Text(
                            'worker_profile_preview'.tr(),
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
                              image: DecorationImage(
                                image: getProfileImage(profileImage, email, 0),
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
                                        'active'.tr(),
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
                                      child: Tooltip(
                                        message: email,
                                        child: Text(
                                          email,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            color: Color(0xFFFFFFFF),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),

                                // Phone Row
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 3),
                                      child: Icon(
                                        Icons.phone,
                                        color: Color(0xFFFFFFFF),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        phone.isNotEmpty ? phone : 'na'.tr(),
                                        style: const TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
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
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Row 1
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              Icons.person,
                              'father_husband_name'.tr(),
                              fatherName.isNotEmpty ? fatherName : 'na'.tr(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Exact spelling from image ("Postion")
                          Expanded(
                            child: _buildInfoCard(
                              Icons.business_center,
                              'postion'.tr(),
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
                              'attendance_type'.tr(),
                              attendanceType,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              Icons.schedule,
                              'work_type'.tr(),
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
                              'experience_level'.tr(),
                              experienceLevel.isNotEmpty
                                  ? experienceLevel
                                  : 'na'.tr(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              Icons.calendar_month,
                              'joining_date'.tr(),
                              joiningDate.isNotEmpty ? joiningDate : 'na'.tr(),
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
                              'gender'.tr(),
                              gender.isNotEmpty ? gender : 'male'.tr(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              Icons.volunteer_activism,
                              'salary'.tr(),
                              salary.isNotEmpty ? salary : 'na'.tr(),
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
      ),
    );
  }

  // --- Helper Widget for the Cards ---
  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cardBorderGrey, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.bold,
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
