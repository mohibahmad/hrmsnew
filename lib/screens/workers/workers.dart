
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/screens/workers/add_worker_flow.dart';
import 'package:hrms/screens/workers/add_bulk_worker_screen.dart';
import 'package:hrms/widgets/dialogs/unsaved_changes_dialog.dart';
import 'package:hrms/widgets/common/notification_bell.dart';
import 'package:hrms/widgets/common/amount_text.dart';
import 'package:hrms/widgets/common/screen_table_shimmer.dart';
import 'package:hrms/services/workers/worker_profile_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hrms/riverpod_providers.dart';

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

String? _workerDateText(dynamic value) {
  if (value == null) return null;
  final date = AppDateUtils.dateFromValue(value);
  return date != null ? AppDateUtils.formatDate(date) : value.toString();
}

const _kFontFamily = 'SF Pro Display';

const _kWhite = AppColors.white;
const _kBlack = AppColors.black;
const _kPrimaryBlue = AppColors.primaryBlue;
const _kDarkBlue = AppColors.primaryBlueDark;
const _kActionBtnBlue = AppColors.actionBlue;
const _kButtonColor = AppColors.buttonBlue;
const _kFilterSelected = AppColors.filterSelected;
const _kRowBg = AppColors.bgGrey;
const _kBorder = AppColors.borderLight;
const _kDivider = AppColors.divider;
const _kMenuBg = Color(0xFFFBFBFC);
const _kMenuBorder = AppColors.borderMenu;
const _kSearchIcon = Color(0xFFBDBDBD);

const _kHeaderTextStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 16,
  fontFamily: _kFontFamily,
  color: Colors.black,
);

const _kCellTextStyle = TextStyle(
  fontWeight: FontWeight.w500,
  fontSize: 15,
  fontFamily: _kFontFamily,
);

class WorkersScreen extends ConsumerStatefulWidget {
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
  ConsumerState<WorkersScreen> createState() => WorkersScreenState();
}

class WorkersScreenState extends ConsumerState<WorkersScreen> {
  bool _isAddingWorker = false;
  bool _isAddingBulkWorker = false;
  Map<String, dynamic>? _workerToEdit;

  final GlobalKey<AddBulkWorkerScreenState> _bulkWorkerKey =
      GlobalKey<AddBulkWorkerScreenState>();

  bool get isAddingWorker => _isAddingWorker;
  bool get isAddingBulkWorker => _isAddingBulkWorker;

  bool get hasUnsavedBulkChanges =>
      _isAddingBulkWorker &&
      _bulkWorkerKey.currentState?.hasUnsavedChanges == true;

  bool get hasUnsavedChanges =>
      _isAddingWorker ||
      (_isAddingBulkWorker &&
          _bulkWorkerKey.currentState?.hasUnsavedChanges == true);

  Future<bool> confirmDiscardBulkChanges() async {
    if (!hasUnsavedBulkChanges) return true;
    return _bulkWorkerKey.currentState?.confirmDiscard() ?? true;
  }

  Future<bool> confirmDiscardChanges() async {
    if (!hasUnsavedChanges) return true;

    if (_isAddingWorker) {
      final shouldDiscard = await UnsavedChangesDialog.show(context);
      if (shouldDiscard) {
        setState(() {
          _isAddingWorker = false;
          _workerToEdit = null;
        });
      }
      return shouldDiscard;
    }

    if (_isAddingBulkWorker) {
      final shouldDiscard = await confirmDiscardBulkChanges();
      if (shouldDiscard) {
        setState(() => _isAddingBulkWorker = false);
      }
      return shouldDiscard;
    }

    return true;
  }

  void closeIdleBulkAddFlow() {
    if (!_isAddingBulkWorker) return;
    if (_bulkWorkerKey.currentState?.hasUnsavedChanges == true) return;
    if (!mounted) return;
    setState(() => _isAddingBulkWorker = false);
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
    }

    if (_isAddingBulkWorker) {
      return AddBulkWorkerScreen(
        key: _bulkWorkerKey,
        onBack: () {
          setState(() => _isAddingBulkWorker = false);
        },
      );
    }

    return DashboardWorkerList(
      onAddWorker: () {
        setState(() {
          _isAddingWorker = true;
          _workerToEdit = null;
        });
      },
      onAddBulkWorker: () {
        setState(() => _isAddingBulkWorker = true);
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

class DashboardWorkerList extends ConsumerStatefulWidget {
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
  ConsumerState<DashboardWorkerList> createState() =>
      _DashboardWorkerListState();
}

class _DashboardWorkerListState extends ConsumerState<DashboardWorkerList> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _allWorkers = <Map<String, dynamic>>[];
  bool _isLoading = true;
  String? _loadErrorMessage;
  bool _isOpeningAddFlow = false;
  final Set<String> _deletingWorkerIds = <String>{};

  late AuthService _authService;
  late FirestoreService _firestore;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    _loadWorkers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadWorkers() {
    if (_isGuest) {
      final guestWorkers = DummyData.workers.asMap().entries.map((entry) {
        final w = Map<String, dynamic>.from(entry.value);
        w['profileImage'] = entry.key.isEven
            ? 'assets/boy.png'
            : 'assets/imageplaceholder.png';
        w['workType'] = w['workType'] ?? w['type1'] ?? '';
        w['attendanceType'] = w['attendanceType'] ?? w['type2'] ?? '';
        return w;
      }).toList();

      setState(() {
        _allWorkers = guestWorkers;
        _isLoading = false;
      });
      return;
    }

    ref.listenAsync(
      workersProvider,
      (records) {
        if (!mounted) return;
        final sortedList = records
            .where((w) => w['isDeleted'] != true && w['status'] != 'Terminated')
            .toList();

        sortedList.sort((a, b) {
          final aDate = _workerDateTime(a['updatedAt'] ?? a['createdAt']);
          final bDate = _workerDateTime(b['updatedAt'] ?? b['createdAt']);

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

        setState(() {
          _allWorkers = sortedList;
          _loadErrorMessage = null;
          _isLoading = false;
        });
      },
      onError: (Object e, StackTrace stackTrace) {
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

  bool _matchesFilter(String position, String filter) {
    if (filter == 'All') return true;
    return position.toLowerCase().contains(filter.toLowerCase());
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final query = _searchQuery.trim().toLowerCase();

    final list = _allWorkers.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final position = (doc['position'] ?? '').toString().toLowerCase();
      return (name.contains(query) || position.contains(query)) &&
          _matchesFilter(position, _selectedFilter);
    }).toList();

    list.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return list;
  }

  Future<void> _deleteWorker(Map<String, dynamic> worker) async {
    final normalizedId = (worker['id'] ?? '').toString().trim();
    final workerName = (worker['name'] ?? '').toString().trim();

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
    try {
      if (_isGuest) {
        DummyData.workers.removeWhere(
          (w) => w['id']?.toString() == normalizedId,
        );
        await DummyData.saveToPrefs();
        if (mounted) {
          setState(() => _allWorkers = DummyData.workers);
        }
      } else {
        await _firestore.deleteWorker(normalizedId);
        if (mounted) {
          setState(() {
            _allWorkers.removeWhere(
              (w) => (w['id'] ?? '').toString().trim() == normalizedId,
            );
          });
        }
      }

      if (mounted) {
        final successMsg = workerName.isNotEmpty
            ? '$workerName ${'has_been_removed_successfully'.tr()}'
            : 'worker_deleted_successfully'.tr();
        FlashySnackBar.show(context, message: successMsg);
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

      if ((bulk && _allWorkers.isEmpty && !isPremium) ||
          !PremiumGate.canAddEntry(
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
    const defaultPositions = LocalizationHelper.defaultJobPositions;
    final seenPositionKeys = <String>{};
    final actualPositions = <String>[];

    for (final w in _allWorkers) {
      final pos = (w['position'] ?? '').toString().trim();
      if (pos.isNotEmpty) {
        final key = pos.toLowerCase();
        if (seenPositionKeys.add(key)) {
          actualPositions.add(pos);
        }
      }
    }

    actualPositions.sort();
    final sortedPositions = actualPositions;
    final positionsToShow = <String>[...sortedPositions];

    for (final position in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) =>
            item.toLowerCase().contains(position.toLowerCase()) ||
            position.toLowerCase().contains(item.toLowerCase()),
      );
      if (!alreadyIncluded) positionsToShow.add(position);
    }

    return Container(
      width: double.infinity,
      height: 46,
      decoration: const BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i <= positionsToShow.length; i++) ...[
              _buildFilterTab(
                i == 0 ? 'All' : positionsToShow[i - 1],
                i == 0
                    ? 'all_filter'.tr()
                    : LocalizationHelper.localizePosition(
                        positionsToShow[i - 1],
                      ),
              ),
              if (i < positionsToShow.length)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: 1,
                    height: 16,
                    color: const Color(0xFFE5E7EB).withValues(alpha: 0.5),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWorkers;
    final screenHeight = MediaQuery.of(context).size.height;
    final dynamicHeight = (screenHeight - 279).clamp(495.0, 1200.0);
    final hasProfileTap =
        widget.onProfileTap != null && widget.onLogout != null;

    return Column(
      children: [
        Container(
          height: 94,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          decoration: const BoxDecoration(
            color: _kWhite,
            border: Border(bottom: BorderSide(color: _kBorder, width: 1)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'worker_management'.tr(),
                    style: const TextStyle(
                      color: _kBlack,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFamily: _kFontFamily,
                    ),
                  ),
                  Text(
                    'complete_required_fields_worker'.tr(),
                    style: const TextStyle(
                      color: _kBlack,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: _kFontFamily,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              NotificationBell(onTap: widget.onNotificationTap),
              SizedBox(width: hasProfileTap ? 20 : 24),
              if (hasProfileTap)
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: const UserAvatar(),
                )
              else
                const UserAvatar(),
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
                          color: _kWhite,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/search icon.svg',
                              width: 24,
                              height: 24,
                              colorFilter: const ColorFilter.mode(
                                _kSearchIcon,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) {
                                  setState(() => _searchQuery = val);
                                },
                                decoration: InputDecoration(
                                  hintText: 'search_workers_name_position'.tr(),
                                  hintStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                    fontFamily: _kFontFamily,
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
                                  setState(() => _searchQuery = '');
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
                        if (_isGuest) {
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
                        if (_isGuest) {
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
                  _buildShimmerTable(dynamicHeight)
                else if (_loadErrorMessage != null)
                  SizedBox(
                    width: double.infinity,
                    height: (screenHeight - 320).clamp(300.0, 900.0),
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
                            fontFamily: _kFontFamily,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (filtered.isEmpty)
                  Container(
                    width: double.infinity,
                    height: dynamicHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kWhite,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                            color: _kPrimaryBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: _kFontFamily,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _buildTable(filtered, dynamicHeight),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> workers, double tableHeight) {
    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                _tableHeader('worker_name'.tr(), flex: 3),
                _tableHeader('work_type'.tr(), flex: 2),
                _tableHeader('position'.tr(), flex: 2),
                _tableHeader('attendance_type'.tr(), flex: 2),
                const SizedBox(width: 48),
              ],
            ),
          ),
          const SizedBox(height: 1, child: ColoredBox(color: _kDivider)),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: workers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildListItem(workers[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerTable(double tableHeight) {
    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                _tableHeader('worker_name'.tr(), flex: 3),
                _tableHeader('work_type'.tr(), flex: 2),
                _tableHeader('position'.tr(), flex: 2),
                _tableHeader('attendance_type'.tr(), flex: 2),
                const SizedBox(width: 48),
              ],
            ),
          ),
          const SizedBox(height: 1, child: ColoredBox(color: _kDivider)),
          Expanded(
            child: DelayedShimmer(
              child: Shimmer.fromColors(
                baseColor: screenShimmerBaseColor,
                highlightColor: screenShimmerHighlightColor,
                period: screenShimmerPeriod,
                direction: ShimmerDirection.ltr,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: _kRowBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 100,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 60,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            width: 80,
                            height: 12,
                            margin: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            width: 80,
                            height: 12,
                            margin: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            width: 80,
                            height: 12,
                            margin: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Text(label, style: _kHeaderTextStyle),
      ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? '').toString();
    final email = (worker['email'] ?? '').toString();
    final workType = (worker['workType'] ?? worker['type1'] ?? '').toString();
    final position = (worker['position'] ?? worker['role'] ?? '').toString();
    final attendanceType = (worker['attendanceType'] ?? worker['type2'] ?? '')
        .toString();
    final profileImage = _safeOptionalString(worker['profileImage']);

    final localizedWorkType = LocalizationHelper.localizeWorkType(workType);
    final localizedAttendanceType = LocalizationHelper.localizeAttendanceType(attendanceType);

    void handleMenuAction(String value) {
      if (_isGuest) {
        showGuestRestrictionDialog(context);
        return;
      }

      switch (value) {
        case 'preview':
          showDialog(
            context: context,
            barrierColor: _kPrimaryBlue.withValues(alpha: 0.5),
            builder: (_) => WorkerProfilePreviewDialog(worker: worker),
          );
        case 'edit':
          widget.onEditWorker?.call(worker);
        case 'delete':
          _deleteWorker(worker);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: _kRowBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
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
                            fontFamily: _kFontFamily,
                          ),
                        ),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            fontFamily: _kFontFamily,
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
              padding: const EdgeInsets.only(right: 24),
              child: Text(
                localizedWorkType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _kCellTextStyle,
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Text(
                LocalizationHelper.localizePosition(position),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _kCellTextStyle,
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              localizedAttendanceType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _kCellTextStyle,
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
                side: const BorderSide(color: _kMenuBorder),
              ),
              color: _kMenuBg,
              elevation: 8,
              offset: const Offset(0, 40),
              constraints: const BoxConstraints(maxWidth: 190),
              onSelected: handleMenuAction,
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'preview',
                  height: 48,
                  child: _MenuItemRow(
                    icon: const Icon(
                      Icons.remove_red_eye,
                      size: 16,
                      color: _kBlack,
                    ),
                    label: 'preview'.tr(),
                    textColor: _kBlack,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'edit',
                  height: 48,
                  child: _MenuItemRow(
                    icon: const Icon(
                      Icons.edit,
                      size: 16,
                      color: _kActionBtnBlue,
                    ),
                    label: 'edit_worker'.tr(),
                    textColor: _kActionBtnBlue,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  height: 48,
                  child: _MenuItemRow(
                    icon: SvgPicture.asset(
                      'assets/delete_icon.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFFF1014),
                        BlendMode.srcIn,
                      ),
                    ),
                    label: 'delete_worker'.tr(),
                    textColor: const Color(0xFFFF1014),
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
        color: _kButtonColor,
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
                  colorFilter: const ColorFilter.mode(_kWhite, BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kWhite,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    fontFamily: _kFontFamily,
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
    final isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kFilterSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: _kFontFamily,
          ),
        ),
      ),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color textColor;

  const _MenuItemRow({
    required this.icon,
    required this.label,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: _kFontFamily,
            ),
          ),
        ),
      ],
    );
  }
}

class WorkerProfilePreviewDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> worker;

  const WorkerProfilePreviewDialog({super.key, required this.worker});

  @override
  ConsumerState<WorkerProfilePreviewDialog> createState() =>
      _WorkerProfilePreviewDialogState();
}

class _WorkerProfilePreviewDialogState
    extends ConsumerState<WorkerProfilePreviewDialog> {
  static const Color _primaryBlue = Color(0xFF0953D4);
  static const Color _iconLightBlue = Color(0xFFE5EEFC);
  static const Color _cardBorderGrey = Color(0xFFE8E8E8);

  bool _isSharing = false;

  String _workerField(String key) {
    if (key == 'workType' || key == 'type1') {
      final val = widget.worker['workType'] ?? widget.worker['type1'];
      return (val ?? '').toString();
    }
    if (key == 'attendanceType' || key == 'type2') {
      final val = widget.worker['attendanceType'] ?? widget.worker['type2'];
      return (val ?? '').toString();
    }
    return (widget.worker[key] ?? '').toString();
  }

  String _orNA(String value) => value.trim().isNotEmpty ? value : 'na'.tr();

  String _capitalizeWords(String text) => Validators.titleCase(text);

  String _formatSalary(String salaryAmount, {String? currencyOverride}) {
    final companyCurr =
        currencyOverride ?? PreferencesService.cachedCompanyCurrency;
    final currSymbol = CurrencyUtils.symbolFor(companyCurr);
    final rawSalaryStr = salaryAmount.trim();
    final salaryToFormat =
        rawSalaryStr.isNotEmpty && rawSalaryStr.startsWith(RegExp(r'\d'))
        ? '$currSymbol $rawSalaryStr'
        : rawSalaryStr;
    return salaryToFormat.isNotEmpty
        ? AmountText.formatCompact(
            salaryToFormat,
            locale: context.locale.toString(),
          )
        : '';
  }

  Future<void> _handlePdfExport({required bool isShare}) async {
    if (_isSharing) return;
    final isGuest =
        ref.read(authServiceProvider).currentUser?.isAnonymous ?? false;
    if (isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }
    setState(() => _isSharing = true);

    try {
      final worker = widget.worker;
      final name = _workerField('name');
      final email = _workerField('email');
      final phone = (worker['phone'] ?? worker['contact'] ?? '').toString();
      final profileImage = _safeOptionalString(worker['profileImage']);
      final salaryAmount = _workerField('salaryAmount');

      Map<String, dynamic> companyProfile = const {};
      try {
        companyProfile =
            await CompanyProfileHelper.getCompanyProfileWithFirestore(
              ref.read(firestoreServiceProvider),
            );
      } catch (e) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'error_occurred'.tr(namedArgs: {'error': e.toString()}),
            isError: true,
          );
        }
        return;
      }

      if (!mounted) return;

      final companyCurr = companyProfile['currency']?.toString().trim();
      final salary = _formatSalary(salaryAmount, currencyOverride: companyCurr);

      final companyName = CompanyProfileHelper.companyNameOrFallback(
        (companyProfile['companyName'] ?? companyProfile['businessName'] ?? '')
            .toString(),
      );
      final companyId =
          (companyProfile['companyId'] ?? companyProfile['businessId'] ?? '')
              .toString();

      final bytes = await WorkerProfileService.generateWorkerProfile(
        name: name,
        email: email,
        phone: phone,
        fatherHusbandName: _orNA(_workerField('fatherName')),
        position: _capitalizeWords(_workerField('position')),
        nationalId: _orNA(_workerField('nationalId')),
        attendanceType: LocalizationHelper.localizeAttendanceType(_workerField('attendanceType')),
        workType: LocalizationHelper.localizeWorkType(_workerField('workType')),
        experienceLevel: _orNA(
          LocalizationHelper.localizeExperience(
            _workerField('experienceLevel'),
          ),
        ),
        gender: _orNA(
          LocalizationHelper.localizeGender(_workerField('gender')),
        ),
        joiningDate: _orNA(_workerDateText(worker['joiningDate']) ?? ''),
        salary: salary,
        education: _orNA(
          LocalizationHelper.localizeEducation(_workerField('education')),
        ),
        religion: _orNA(_workerField('religion')),
        dateOfBirth: _orNA(_workerDateText(worker['dob']) ?? ''),
        relationshipStatus: _orNA(
          LocalizationHelper.localizeRelationshipStatus(
            _workerField('relationshipStatus'),
          ),
        ),
        address: _orNA(_workerField('address')),
        profileImageUrl: profileImage,
        generatedOnText:
            '${'generated_on'.tr()} ${DateTime.now().toString().substring(0, 10)}',
        companyName: companyName,
        companyId: companyId,
        companyStampImageUrl: (companyProfile['companyStampUrl'] ?? '')
            .toString(),
      ).timeout(const Duration(seconds: 30));

      final rawName = name.trim();
      final safeName = rawName
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
            message: 'profile_downloaded_opened'.tr(),
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
    final name = _workerField('name');
    final email = _workerField('email');
    final phone = (worker['phone'] ?? worker['contact'] ?? '').toString();
    final profileImage = _safeOptionalString(worker['profileImage']);
    final salaryAmount = _workerField('salaryAmount');
    final salary = _formatSalary(salaryAmount);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 520,
          height: 660,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _kWhite,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: _kBlack.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(color: _kPrimaryBlue),
                child: Column(
                  children: [
                    Container(
                      height: 44,
                      decoration: const BoxDecoration(color: _kDarkBlue),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            'worker_profile_preview'.tr(),
                            style: const TextStyle(
                              color: _kWhite,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: _kFontFamily,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: _kWhite,
                                  size: 24,
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                              ),
                            ),
                          ),
                          Align(
                            alignment: const Alignment(1.0, 0),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: IconButton(
                                icon: _isSharing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : SvgPicture.asset(
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
                              border: Border.all(color: _kWhite, width: 2),
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
                                    color: _kWhite,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: _kFontFamily,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: SvgPicture.asset(
                                        'assets/email.svg',
                                        width: 16,
                                        height: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _kWhite,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: _kFontFamily,
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
                                          color: _kWhite,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: _kFontFamily,
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
                          _orNA(_workerField('fatherName')),
                        ),
                        _buildInfoCard(
                          Icons.business_center,
                          'position'.tr(),
                          LocalizationHelper.localizePosition(
                            _workerField('position'),
                          ),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.badge,
                          'national_id'.tr(),
                          _orNA(_workerField('nationalId')),
                        ),
                        _buildInfoCard(
                          Icons.location_on,
                          'attendance_type'.tr(),
                          LocalizationHelper.localizeAttendanceType(
                            _workerField('attendanceType'),
                          ),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.schedule,
                          'work_type'.tr(),
                          LocalizationHelper.localizeWorkType(
                            _workerField('workType'),
                          ),
                          assetImage: 'assets/worktype.png',
                        ),
                        _buildInfoCard(
                          Icons.show_chart,
                          'experience_level'.tr(),
                          _orNA(
                            LocalizationHelper.localizeExperience(
                              _workerField('experienceLevel'),
                            ),
                          ),
                          assetImage: 'assets/experiencelevel.png',
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.transgender,
                          'gender'.tr(),
                          _orNA(
                            LocalizationHelper.localizeGender(
                              _workerField('gender'),
                            ),
                          ),
                        ),
                        _buildInfoCard(
                          Icons.calendar_month,
                          'joining_date'.tr(),
                          _orNA(_workerDateText(worker['joiningDate']) ?? ''),
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
                          _orNA(
                            LocalizationHelper.localizeEducation(
                              _workerField('education'),
                            ),
                          ),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.art_track,
                          'religion_title'.tr(),
                          _orNA(_workerField('religion')),
                          assetImage: 'assets/religion.png',
                        ),
                        _buildInfoCard(
                          Icons.cake,
                          'date_of_birth'.tr(),
                          _orNA(_workerDateText(worker['dob']) ?? ''),
                        ),
                      ),
                      _buildRow(
                        _buildInfoCard(
                          Icons.favorite,
                          'relationship_status'.tr(),
                          _orNA(
                            LocalizationHelper.localizeRelationshipStatus(
                              _workerField('relationshipStatus'),
                            ),
                          ),
                        ),
                        _buildInfoCard(
                          Icons.home,
                          'address'.tr(),
                          _orNA(_workerField('address')),
                        ),
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
    Widget iconWidget;
    if (assetImage != null) {
      if (assetImage.endsWith('.svg')) {
        iconWidget = SvgPicture.asset(
          assetImage,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(_primaryBlue, BlendMode.srcIn),
        );
      } else {
        iconWidget = Image.asset(
          assetImage,
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          color: _primaryBlue,
          colorBlendMode: BlendMode.srcIn,
        );
      }
    } else {
      iconWidget = Icon(icon, color: _primaryBlue, size: 20);
    }

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _cardBorderGrey, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _iconLightBlue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: iconWidget),
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
                    fontSize: 13,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontFamily: _kFontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kBlack,
                    fontWeight: FontWeight.bold,
                    fontFamily: _kFontFamily,
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
