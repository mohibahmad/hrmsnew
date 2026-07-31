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
import '../widgets/notification_bell.dart';
import '../utils/image_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/localization_helper.dart';
import '../utils/guest_restriction.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/amount_text.dart';
import '../services/worker_profile_service.dart';
import 'package:provider/provider.dart';

String? _safeOptionalString(dynamic value) {
  if (value is! String) return null;
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.toLowerCase() == 'null') return null;
  return normalized;
}

DateTime? _workerDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

void main() {
  runApp(const WorkerManagementApp());
}

class WorkerManagementApp extends StatelessWidget {
  const WorkerManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'worker_management'.tr(),
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
  int _currentMenuIndex = 1;
  bool _isPremium = false;
  bool _isOpeningSubscription = false;
  late AuthService _authService;

  final Color sidebarBlue = const Color(0xFF0B50C3);
  final Color activeTabBlue = const Color(0xFF4C84E0);

  final GlobalKey<AddBulkWorkerScreenState> _bulkWorkerKey =
      GlobalKey<AddBulkWorkerScreenState>();

  Future<void> _navigateTo(int index) async {
    if (index == _currentMenuIndex) return;
    if (_currentMenuIndex == 2 &&
        _bulkWorkerKey.currentState?.hasUnsavedChanges == true) {
      final shouldPop = await _bulkWorkerKey.currentState!.confirmDiscard();
      if (!mounted || !shouldPop) return;
    }
    if (!mounted) return;
    setState(() => _currentMenuIndex = index);
  }

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _loadPremiumStatus();
  }

  Future<void> _loadPremiumStatus() async {
    try {
      final isPremium = await PreferencesService.isPremium();
      if (!mounted) return;
      setState(() {
        _isPremium = isPremium;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPremium = false;
      });
    }
  }

  Future<void> _openSubscriptionDialog() async {
    if (_isOpeningSubscription) return;
    _isOpeningSubscription = true;
    try {
      await showDialog<bool>(
        context: context,
        barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
        builder: (context) => const SubscriptionDialog(),
      );
      if (!mounted) return;
      final isPremium = await PreferencesService.isPremium();
      if (!mounted) return;
      setState(() {
        _isPremium = isPremium;
      });
    } finally {
      _isOpeningSubscription = false;
    }
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
                if (!(_authService.currentUser?.isAnonymous ?? false) &&
                    !_isPremium)
                  GestureDetector(
                    onTap: _openSubscriptionDialog,
                    child: Container(
                      width: 238,
                      margin: const EdgeInsets.only(
                        top: 16,
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
                const SizedBox(height: 16),

                _buildNavItem(
                  Icons.grid_view_rounded,
                  'sidebar_dashboard'.tr(),
                  _currentMenuIndex == 0,
                  onTap: () => _navigateTo(0),
                ),
                _buildNavItem(
                  Icons.people_alt,
                  'sidebar_workers'.tr(),
                  _currentMenuIndex == 1,
                  onTap: () => _navigateTo(1),
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

          Expanded(
            child: IndexedStack(
              index: _currentMenuIndex,
              children: [
                DashboardWorkerList(
                  onAddWorker: () => setState(() => _currentMenuIndex = 1),
                  onAddBulkWorker: () => setState(() => _currentMenuIndex = 2),
                ),
                AddNewWorkerFlow(
                  onBack: () => setState(() => _currentMenuIndex = 0),
                ),
                AddBulkWorkerScreen(
                  key: _bulkWorkerKey,
                  onBack: () => setState(() => _currentMenuIndex = 0),
                ),
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
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
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
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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
  State<WorkersScreen> createState() => WorkersScreenState();
}

class WorkersScreenState extends State<WorkersScreen> {
  bool _isAddingWorker = false;
  bool _isAddingBulkWorker = false;
  Map<String, dynamic>? _workerToEdit;
  final GlobalKey<AddBulkWorkerScreenState> _bulkWorkerKey =
      GlobalKey<AddBulkWorkerScreenState>();

  bool get hasUnsavedBulkChanges =>
      _isAddingBulkWorker &&
      _bulkWorkerKey.currentState?.hasUnsavedChanges == true;

  Future<bool> confirmDiscardBulkChanges() async {
    if (!hasUnsavedBulkChanges) return true;
    return _bulkWorkerKey.currentState?.confirmDiscard() ?? true;
  }

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
        key: _bulkWorkerKey,
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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _allWorkers = [];
  bool _isLoading = true;
  String? _loadErrorMessage;
  bool _isOpeningAddFlow = false;
  final Set<String> _deletingWorkerIds = <String>{};
  StreamSubscription? _workersSub;
  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void dispose() {
    _workersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    _allWorkers = [];
    _isLoading = true;
    _loadWorkers();
  }

  void _loadWorkers() {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _allWorkers = DummyData.workers
            .map((w) => Map<String, dynamic>.from(w))
            .toList();

        for (int i = 0; i < _allWorkers.length; i++) {
          _allWorkers[i]['profileImage'] = i.isEven
              ? 'assets/boy.png'
              : 'assets/imageplaceholder.png';

          _allWorkers[i]['type1'] = _allWorkers[i]['workType'] ?? '';
          _allWorkers[i]['type2'] = _allWorkers[i]['attendanceType'] ?? '';
        }
        _isLoading = false;
      });
    } else {
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (!mounted) return;
          setState(() {
            final sortedList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            sortedList.sort((a, b) {
              final aDate = _workerDateTime(a['createdAt']);
              final bDate = _workerDateTime(b['createdAt']);
              if (aDate == null && bDate == null) {
                return (a['name'] ?? '').toString().toLowerCase().compareTo(
                  (b['name'] ?? '').toString().toLowerCase(),
                );
              }
              if (aDate == null) return 1;
              if (bDate == null) return -1;
              final dateOrder = bDate.compareTo(aDate);
              if (dateOrder != 0) return dateOrder;
              return (a['name'] ?? '').toString().toLowerCase().compareTo(
                (b['name'] ?? '').toString().toLowerCase(),
              );
            });
            _allWorkers = sortedList;
            _loadErrorMessage = null;
            _isLoading = false;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _loadErrorMessage = 'failed_to_load_worker_data'.tr(
              namedArgs: {'error': e.toString()},
            );
            _isLoading = false;
          });
        },
      );
    }
  }

  bool _matchesFilter(String position, String filter) {
    if (filter == 'All') return true;
    return position.toLowerCase().contains(filter.toLowerCase());
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    return _allWorkers.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final position = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.trim().toLowerCase();

      final matchesSearch = name.contains(query) || position.contains(query);
      final matchesFilter = _matchesFilter(position, _selectedFilter);

      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _deleteWorker(String docId) async {
    final normalizedId = docId.trim();
    if (normalizedId.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'unexpected_error'.tr(),
        isError: true,
      );
      return;
    }
    if (_deletingWorkerIds.contains(normalizedId)) return;

    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_worker'.tr(),
      content: 'delete_worker_desc'.tr(),
    );
    if (!confirmed || !mounted) return;

    _deletingWorkerIds.add(normalizedId);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    try {
      if (isGuest) {
        DummyData.workers.removeWhere(
          (w) => w['id']?.toString() == normalizedId,
        );
        await DummyData.saveToPrefs();
        if (mounted) {
          setState(() {
            _allWorkers = DummyData.workers;
          });
        }
      } else {
        await _firestore.deleteWorker(normalizedId);
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
          message: 'error_occurred'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    } finally {
      _deletingWorkerIds.remove(normalizedId);
    }
  }

  Future<void> _openAuthenticatedAddFlow({required bool bulk}) async {
    if (_isOpeningAddFlow) return;
    _isOpeningAddFlow = true;
    try {
      var isPremium = await PreferencesService.isPremium();
      if (!mounted) return;

      if (!PremiumGate.canAddEntry(
        currentEntryCount: _allWorkers.length,
        isPremium: isPremium,
        isGuest: false,
      )) {
        await PremiumGate.shouldShowUpgradeDialog(context);
        if (!mounted) return;
        isPremium = await PreferencesService.isPremium();
        if (!mounted || !isPremium) return;
      }

      if (bulk) {
        widget.onAddBulkWorker?.call();
      } else {
        widget.onAddWorker();
      }
    } finally {
      _isOpeningAddFlow = false;
    }
  }

  Widget _buildFilterTabs() {
    const defaultPositions = [
      'Designer',
      'Developer',
      'Engineering',
      'Sales',
      'Management',
    ];
    final actualPositions = <String>{};
    final positionNormalizer = <String, String>{};
    for (final w in _allWorkers) {
      final pos = (w['position'] ?? '').toString().trim();
      if (pos.isNotEmpty) {
        final key = pos.toLowerCase();
        if (!positionNormalizer.containsKey(key)) {
          positionNormalizer[key] = pos;
          actualPositions.add(pos);
        }
      }
    }
    final sortedPositions = actualPositions.toList()..sort();

    final positionsToShow = <String>[...sortedPositions];
    for (final position in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) =>
            item.toLowerCase().contains(position.toLowerCase()) ||
            position.toLowerCase().contains(item.toLowerCase()),
      );
      if (!alreadyIncluded) {
        positionsToShow.add(position);
      }
    }

    final filters = <Map<String, String>>[
      {'key': 'All', 'label': 'all_filter'.tr()},
      ...positionsToShow.map((p) => {'key': p, 'label': p}),
    ];
    return Container(
      width: 550,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < filters.length; i++)
              _buildFilterTab(filters[i]['key']!, filters[i]['label']!),
          ],
        ),
      ),
    );
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
                NotificationBell(onTap: widget.onNotificationTap),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: const UserAvatar(),
                ),
              ] else ...[
                NotificationBell(onTap: widget.onNotificationTap),
                const SizedBox(width: 24),
                const UserAvatar(),
              ],
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 40.0,
              vertical: 22.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                controller: _searchController,
                                onChanged: (val) {
                                  setState(() {
                                    _searchQuery = val;
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
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildActionButton(
                      svgPath: 'assets/add_worker.svg',
                      label: 'add_worker'.tr(),
                      onTap: () async {
                        final isGuest =
                            _authService.currentUser?.isAnonymous ?? false;
                        if (isGuest) {
                          if (!mounted) return;
                          showGuestRestrictionDialog(context);
                          return;
                        }
                        await _openAuthenticatedAddFlow(bulk: false);
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildActionButton(
                      svgPath: 'assets/add_bulk_worker.svg',
                      label: 'add_bulk_workers'.tr(),
                      onTap: () async {
                        final isGuest =
                            _authService.currentUser?.isAnonymous ?? false;
                        if (isGuest) {
                          if (!mounted) return;
                          showGuestRestrictionDialog(context);
                          return;
                        }
                        await _openAuthenticatedAddFlow(bulk: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                _buildFilterTabs(),
                const SizedBox(height: 22),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_loadErrorMessage != null)
                  SizedBox(
                    width: double.infinity,
                    height: (MediaQuery.of(context).size.height - 320).clamp(
                      300.0,
                      900.0,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _loadErrorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ),
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

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _filteredWorkers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildListItem(_filteredWorkers[index], index);
              },
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
    final profileImage = _safeOptionalString(worker['profileImage']);
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
                  WorkerAvatar(imageUrl: profileImage, name: name, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            fontFamily: 'SF Pro Display',
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
                overflow: TextOverflow.ellipsis,
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
              child: Text(
                position,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
            child: Text(
              localizedType2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
              tooltip: '',
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
                  showDialog(
                    context: context,
                    barrierColor: const Color(
                      0xFF0247C4,
                    ).withValues(alpha: 0.5),
                    builder: (context) =>
                        WorkerProfilePreviewDialog(worker: worker),
                  );
                } else if (value == 'edit') {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  widget.onEditWorker?.call(worker);
                } else if (value == 'delete') {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  _deleteWorker(docId);
                }
              },
              constraints: const BoxConstraints(maxWidth: 168),
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'preview',
                  height: 48,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_red_eye,
                        size: 16,
                        color: Color(0xFF000000),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'preview'.tr(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'edit',
                  height: 48,
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16, color: actionBtnBlue),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'edit_worker'.tr(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: actionBtnBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  height: 48,
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
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'delete'.tr(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
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
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String svgPath,
    required String label,
    required VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: buttonColor,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
    final bool isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedFilter = filterKey;
      }),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 16,
          vertical: 8,
        ),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D4CB6) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }
}

class WorkerProfilePreviewDialog extends StatefulWidget {
  final Map<String, dynamic> worker;

  const WorkerProfilePreviewDialog({super.key, required this.worker});

  @override
  State<WorkerProfilePreviewDialog> createState() =>
      _WorkerProfilePreviewDialogState();
}

class _WorkerProfilePreviewDialogState
    extends State<WorkerProfilePreviewDialog> {
  bool _isSharing = false;
  final Color primaryBlue = const Color(0xFF0953D4);
  final Color iconLightBlue = const Color(0xFFE5EEFC);
  final Color cardBorderGrey = const Color(0xFFE8E8E8);

  String _v(Map<String, dynamic> w, String key) => (w[key] ?? '').toString();
  String _na(String value) => value.trim().isNotEmpty ? value : 'na'.tr();

  String _localizedGender(String value) {
    switch (value.trim().toLowerCase()) {
      case 'male':
        return 'male'.tr();
      case 'female':
        return 'female'.tr();
      case 'other':
      case 'others':
        return 'other'.tr();
      default:
        return value;
    }
  }

  String _localizedRelationshipStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'single':
        return 'single'.tr();
      case 'married':
        return 'married'.tr();
      default:
        return value;
    }
  }

  Future<void> _handlePdfExport({required bool isShare}) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final worker = widget.worker;
      final name = _v(worker, 'name');
      final email = _v(worker, 'email');
      final phone = _v(worker, 'phone');
      final profileImage = _safeOptionalString(worker['profileImage']);
      final currency = CurrencyUtils.normalize(_v(worker, 'currency'));
      final salaryAmount = _v(worker, 'salaryAmount');
      final rawSalary = salaryAmount.isNotEmpty
          ? (currency.isNotEmpty ? '$currency $salaryAmount' : salaryAmount)
          : '';
      final salary = rawSalary.isNotEmpty
          ? AmountText.formatCompact(rawSalary)
          : '';

      final bytes = await WorkerProfileService.generateWorkerProfile(
        name: name,
        email: email,
        phone: phone,
        fatherHusbandName: _na(_v(worker, 'fatherName')),
        position: _v(worker, 'position'),
        nationalId: _na(_v(worker, 'nationalId')),
        attendanceType: LocalizationHelper.localizeType2(_v(worker, 'type2')),
        workType: LocalizationHelper.localizeType1(_v(worker, 'type1')),
        experienceLevel: _na(
          LocalizationHelper.localizeExperience(_v(worker, 'experienceLevel')),
        ),
        gender: _na(_localizedGender(_v(worker, 'gender'))),
        joiningDate: _na(_v(worker, 'joiningDate')),
        salary: salary,
        education: _na(
          LocalizationHelper.localizeEducation(_v(worker, 'education')),
        ),
        salaryType: _na(
          LocalizationHelper.localizeSalaryType(_v(worker, 'salaryType')),
        ),
        religion: _na(_v(worker, 'religion')),
        dateOfBirth: _na(_v(worker, 'dob')),
        relationshipStatus: _na(
          _localizedRelationshipStatus(_v(worker, 'relationshipStatus')),
        ),
        address: _na(_v(worker, 'address')),
        profileImageUrl: profileImage,
        generatedOnText:
            '${'generated_on'.tr()} ${DateTime.now().toString().substring(0, 10)}',
      ).timeout(const Duration(seconds: 30));

      final safeName = name
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final fileName = safeName.isEmpty
          ? 'worker_profile.pdf'
          : '${safeName}_profile.pdf';

      if (isShare) {
        final saved = await WorkerProfileService.shareWorkerProfile(
          bytes,
          fileName,
        );
        if (saved && mounted) {
          FlashySnackBar.show(
            context,
            message: 'profile_shared_successfully'.tr(),
          );
        }
      } else {
        final saved = await WorkerProfileService.downloadWorkerProfile(
          bytes,
          fileName,
        );
        if (saved && mounted) {
          FlashySnackBar.show(
            context,
            message: 'profile_shared_successfully'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_occurred'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final worker = widget.worker;
    final name = _v(worker, 'name');
    final email = _v(worker, 'email');
    final phone = _v(worker, 'phone');
    final profileImage = _safeOptionalString(worker['profileImage']);
    final currency = CurrencyUtils.normalize(_v(worker, 'currency'));
    final salaryAmount = _v(worker, 'salaryAmount');
    final rawSalary = salaryAmount.isNotEmpty
        ? (currency.isNotEmpty ? '$currency $salaryAmount' : salaryAmount)
        : '';
    final salary = rawSalary.isNotEmpty
        ? AmountText.formatCompact(rawSalary)
        : '';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 520,
          height: 660,
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
              Container(
                decoration: const BoxDecoration(color: Color(0xFF0247C4)),
                child: Column(
                  children: [
                    Container(
                      height: 44,
                      decoration: const BoxDecoration(color: Color(0xFF004FDE)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            'worker_profile_preview'.tr(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Color(0xFFFFFFFF),
                                  size: 24,
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment(1.0, 0),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: IconButton(
                                icon: SvgPicture.asset(
                                  'assets/share1.svg',
                                  width: 20,
                                  height: 20,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                onPressed: _isSharing
                                    ? null
                                    : () => _handlePdfExport(isShare: true),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(left: 12),
                            child: WorkerAvatar(
                              imageUrl: profileImage,
                              name: name,
                              size: 130,
                              border: Border.all(
                                color: const Color(0xFFFFFFFF),
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Image.asset(
                                        'assets/email.png',
                                        width: 20,
                                        height: 20,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Image.asset(
                                        'assets/call.png',
                                        width: 20,
                                        height: 20,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        phone.isNotEmpty ? phone : 'na'.tr(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
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
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildRow(
                        _buildInfoCard(
                          Icons.person,
                          'father_husband_name'.tr(),
                          _na(_v(worker, 'fatherName')),
                        ),
                        _buildInfoCard(
                          Icons.business_center,
                          'position'.tr(),
                          _v(worker, 'position'),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.badge,
                          'national_id'.tr(),
                          _na(_v(worker, 'nationalId')),
                        ),
                        _buildInfoCard(
                          Icons.location_on_outlined,
                          'attendance_type'.tr(),
                          LocalizationHelper.localizeType2(_v(worker, 'type2')),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.schedule,
                          'work_type'.tr(),
                          LocalizationHelper.localizeType1(_v(worker, 'type1')),
                        ),
                        _buildInfoCard(
                          Icons.show_chart,
                          'experience_level'.tr(),
                          _na(
                            LocalizationHelper.localizeExperience(
                              _v(worker, 'experienceLevel'),
                            ),
                          ),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.transgender,
                          'gender'.tr(),
                          _na(_localizedGender(_v(worker, 'gender'))),
                        ),
                        _buildInfoCard(
                          Icons.calendar_month,
                          'joining_date'.tr(),
                          _na(_v(worker, 'joiningDate')),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.money,
                          'salary'.tr(),
                          salary.isNotEmpty ? salary : 'na'.tr(),
                          assetImage: 'assets/salary.png',
                        ),
                        _buildInfoCard(
                          Icons.school,
                          'education_title'.tr(),
                          _na(
                            LocalizationHelper.localizeEducation(
                              _v(worker, 'education'),
                            ),
                          ),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.money,
                          'salary_type'.tr(),
                          _na(
                            LocalizationHelper.localizeSalaryType(
                              _v(worker, 'salaryType'),
                            ),
                          ),
                        ),
                        _buildInfoCard(
                          Icons.art_track_outlined,
                          'religion_title'.tr(),
                          _na(_v(worker, 'religion')),
                          assetImage: 'assets/religion.png',
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.cake,
                          'date_of_birth'.tr(),
                          _na(_v(worker, 'dob')),
                        ),
                        _buildInfoCard(
                          Icons.favorite,
                          'relationship_status'.tr(),
                          _na(
                            _localizedRelationshipStatus(
                              _v(worker, 'relationshipStatus'),
                            ),
                          ),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.home,
                          'address'.tr(),
                          _na(_v(worker, 'address')),
                        ),
                        const SizedBox.shrink(),
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

  Widget _buildRow(Widget left, Widget right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String value, {
    String? assetImage,
  }) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cardBorderGrey, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconLightBlue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: assetImage != null
                  ? assetImage.endsWith('.svg')
                        ? SvgPicture.asset(
                            assetImage,
                            width: 18,
                            height: 18,
                            colorFilter: ColorFilter.mode(
                              primaryBlue,
                              BlendMode.srcIn,
                            ),
                          )
                        : Image.asset(
                            assetImage,
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                            color: primaryBlue,
                            colorBlendMode: BlendMode.srcIn,
                          )
                  : Icon(icon, color: primaryBlue, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
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
