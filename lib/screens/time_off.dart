import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/time_off_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/image_utils.dart';
import '../widgets/notification_bell.dart';

import 'assign_time_off.dart';
import '../utils/guest_restriction.dart';

class Worker {
  final String name;
  final String email;
  final String position;
  final String contact;
  final String action;
  final bool isMaleAvatar;

  Worker(
    this.name,
    this.email,
    this.position,
    this.contact,
    this.action,
    this.isMaleAvatar,
  );
}

class TimeOffScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final ValueChanged<Map<String, dynamic>>? onAssignTimeOff;
  final VoidCallback? onNotificationTap;

  const TimeOffScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onAssignTimeOff,
    this.onNotificationTap,
  });

  @override
  State<TimeOffScreen> createState() => _TimeOffScreenState();
}

class _TimeOffScreenState extends State<TimeOffScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTab = 'All';

  List<Map<String, dynamic>> _rawTimeoffDocs = [];
  List<Map<String, dynamic>> _timeoffDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  bool _isLoading = true;

  StreamSubscription? _timeoffSub;
  StreamSubscription? _workersSub;

  bool _isAssigningTimeOff = false;
  Map<String, dynamic>? _workerForTimeOff;
  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void dispose() {
    _timeoffSub?.cancel();
    _workersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _combineTimeOff() {
    if (_workersList.isEmpty) {
      _timeoffDocs = [];
      _isLoading = false;
      return;
    }

    final combined = <Map<String, dynamic>>[];
    for (final worker in _workersList) {
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final name = (worker['name'] ?? '').toString().trim().toLowerCase();
      final matchingRecords = _rawTimeoffDocs.where((record) {
        final tEmail = (record['email'] ?? '').toString().trim().toLowerCase();
        final tName = (record['name'] ?? record['workerName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return (email.isNotEmpty && tEmail == email) ||
            (email.isEmpty && name.isNotEmpty && tName == name);
      }).toList();
      final remaining = TimeOffService.remainingPaidLeave(
        worker,
        _rawTimeoffDocs,
      );

      if (matchingRecords.isEmpty) {
        combined.add({
          ...worker,
          'action': '',
          'startDate': '',
          'endDate': '',
          'requestedDays': 0,
          'remainingLeaves': remaining.toString(),
        });
        continue;
      }

      for (final timeoffRecord in matchingRecords) {
        combined.add({
          ...worker,
          ...timeoffRecord,
          'workerId': worker['id'],
          'profileImage':
              worker['profileImage'] ?? timeoffRecord['profileImage'],
          'phone': worker['phone'] ?? timeoffRecord['phone'] ?? '',
          'contact': worker['phone'] ?? timeoffRecord['contact'] ?? '',
          'remainingLeaves': remaining.toString(),
        });
      }
    }

    combined.sort((a, b) {
      final aHasRecord = (a['action'] ?? '').toString().isNotEmpty;
      final bHasRecord = (b['action'] ?? '').toString().isNotEmpty;
      if (aHasRecord != bHasRecord) return aHasRecord ? -1 : 1;
      final aStart = TimeOffService.parseDate(a['startDate']);
      final bStart = TimeOffService.parseDate(b['startDate']);
      if (aStart == null || bStart == null) return 0;
      return bStart.compareTo(aStart);
    });

    _timeoffDocs = combined;
    _isLoading = false;
  }

  void _refreshGuestData() {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _isLoading = true;
        _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
        _rawTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _combineTimeOff();
      });
    } else {
      setState(() => _combineTimeOff());
    }
  }

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    _rawTimeoffDocs = [];
    _timeoffDocs = [];
    _workersList = [];
    _isLoading = true;
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = _firestore.workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workersList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _combineTimeOff();
          });
        }
      });
      _timeoffSub = _firestore.timeoffStream.listen(
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
              _rawTimeoffDocs = sortedList;
              _combineTimeOff();
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
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
      _combineTimeOff();
    }
  }

  bool _matchesFilter(String position, String filter) {
    if (filter == 'All') return true;
    return position.toLowerCase().contains(filter.toLowerCase());
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final filtered = _timeoffDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final position = (doc['position'] ?? '').toString().toLowerCase();
      final email = (doc['email'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      final matchesSearch =
          name.contains(query) ||
          position.contains(query) ||
          email.contains(query);

      if (!matchesSearch) return false;
      return _matchesFilter(position, _selectedTab);
    }).toList();

    filtered.sort((a, b) {
      final actionA = (a['action'] ?? '').toString();
      final actionB = (b['action'] ?? '').toString();
      if (actionA.isNotEmpty && actionB.isEmpty) return -1;
      if (actionA.isEmpty && actionB.isNotEmpty) return 1;
      return 0;
    });

    return filtered;
  }

  Future<void> _handleDelete(Map<String, dynamic> doc) async {
    final action = (doc['action'] ?? '').toString();
    if (action.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'no_time_off_record_to_delete'.tr(),
          isError: true,
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'delete_time_off'.tr(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'SF Pro Display',
          ),
        ),
        content: Text(() {
          String localizedAction = action;
          if (action == 'Annual Leave') {
            localizedAction = 'annual'.tr();
          } else if (action == 'Sick Leave') {
            localizedAction = 'sick'.tr();
          } else if (action == 'Casual Leave') {
            localizedAction = 'casual'.tr();
          } else if (action == 'Maternity Leave') {
            localizedAction = 'maternity_leave'.tr();
          }
          return '${doc['name'] ?? ''} — $localizedAction';
        }(), style: const TextStyle(fontFamily: 'SF Pro Display')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'cancel'.tr(),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'delete'.tr(),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;

      final recordId = doc['id']?.toString() ?? '';
      final workerEmail = (doc['email'] ?? '').toString().trim().toLowerCase();
      final worker = _workersList.firstWhere(
        (candidate) =>
            (candidate['email'] ?? '').toString().trim().toLowerCase() ==
            workerEmail,
        orElse: () => <String, dynamic>{},
      );
      final projectedRecords = _rawTimeoffDocs
          .where((record) => record['id']?.toString() != recordId)
          .map(Map<String, dynamic>.from)
          .toList();
      final usedPaidDays = worker.isEmpty
          ? 0
          : TimeOffService.paidDaysUsedForWorker(worker, projectedRecords);
      final totalPaidDays = worker.isEmpty
          ? 0
          : TimeOffService.configuredPaidLeaveAllowance(worker);
      final balanceUpdate = <String, dynamic>{
        'availableAnnualLeaves': (totalPaidDays - usedPaidDays)
            .clamp(0, totalPaidDays)
            .toString(),
        'leavesUsed': usedPaidDays.toString(),
      };

      if (isGuest) {
        final workerIndex = DummyData.workers.indexWhere(
          (candidate) =>
              (candidate['email'] ?? '').toString().trim().toLowerCase() ==
              workerEmail,
        );
        if (workerIndex != -1) {
          DummyData.workers[workerIndex].addAll(balanceUpdate);
        }
        DummyData.timeoff.removeWhere((record) => record['id'] == doc['id']);
        await DummyData.saveToPrefs();
        if (mounted) {
          setState(() {
            _rawTimeoffDocs.removeWhere((record) => record['id'] == doc['id']);
            _combineTimeOff();
          });
        }
      } else {
        final workerId = (worker['id'] ?? doc['workerId'] ?? '').toString();
        if (recordId.isNotEmpty && workerId.isNotEmpty) {
          await _firestore.deleteTimeOffWithWorkerBalance(
            timeOffId: recordId,
            workerId: workerId,
            balance: balanceUpdate,
          );
        } else if (recordId.isNotEmpty) {
          await _firestore.deleteTimeOffRecord(recordId);
        }
      }
      if (mounted) {
        FlashySnackBar.show(context, message: 'time_off_record_deleted'.tr());
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
    if (_isAssigningTimeOff && _workerForTimeOff != null) {
      return AssignTimeOffScreen(
        onBack: () {
          setState(() {
            _isAssigningTimeOff = false;
            _workerForTimeOff = null;
          });
          _refreshGuestData();
        },
        initialWorker: _workerForTimeOff,
        onNotificationTap: widget.onNotificationTap,
        onProfileTap: widget.onProfileTap,
      );
    }

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
                  const SizedBox(height: 10),

                  const SizedBox(height: 10),
                  _buildFilterTabs(),
                  const SizedBox(height: 20),
                  Text(
                    'time_off_list'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 20),

                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (filtered.isEmpty
                            ? _buildEmptyState()
                            : _buildDataTable(filtered)),
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
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
            ],
          ),
          const Spacer(),

          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: const UserAvatar(),
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
                _searchController.clear();
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
    const defaultPositions = [
      'Designer',
      'Developer',
      'Engineering',
      'Sales',
      'Management',
    ];
    final actualPositions = <String>{};
    for (final w in _workersList) {
      final pos = (w['position'] ?? '').toString().trim();
      if (pos.isNotEmpty) actualPositions.add(pos);
    }
    final sortedPositions = actualPositions.toList()..sort();

    final positionsToShow = <String>[...sortedPositions];
    for (final position in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) => item.toLowerCase() == position.toLowerCase(),
      );
      if (!alreadyIncluded) {
        positionsToShow.add(position);
      }
    }

    final allFilters = ['All', ...positionsToShow];

    return Container(
      width: 650,
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
            for (final f in allFilters)
              _buildTabItem(f, f == 'All' ? 'all_filter'.tr() : f),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(String filterKey, String displayLabel) {
    final bool isSelected = _selectedTab == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = filterKey;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 16,
          vertical: 8,
        ),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0247C4) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
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

  Widget _buildDataTable(List<Map<String, dynamic>> workers) {
    final double tableHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
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
                      'worker_name_header'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
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
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'contact_no'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      'time_off'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: workers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = workers[index];
                final name = (doc['name'] ?? '').toString();
                final email = (doc['email'] ?? '').toString();
                final position = (doc['position'] ?? '').toString();
                final contact = (doc['contact'] ?? doc['phone'] ?? '')
                    .toString();
                String action = (doc['action'] ?? '').toString();
                final bool hasTimeOff = action.isNotEmpty;
                action = hasTimeOff ? 'assigned'.tr() : 'assign'.tr();
                return GestureDetector(
                  onTap: () {
                    final isGuest =
                        _authService.currentUser?.isAnonymous ?? false;
                    if (isGuest) {
                      showGuestRestrictionDialog(context);
                      return;
                    }
                    _showTimeOffDataDialog(context, doc, index);
                  },
                  onLongPress: (doc['action'] ?? '').toString().isNotEmpty
                      ? () => _handleDelete(doc)
                      : null,
                  child: Container(
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
                                WorkerAvatar(
                                  imageUrl: doc['profileImage']?.toString(),
                                  name: name,
                                  size: 40,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: Color(0xFF000000),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        email,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
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
                              position,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black,
                                fontFamily: 'SF Pro Display',
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ),

                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 24.0),
                            child: Text(
                              contact,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black,
                                fontFamily: 'SF Pro Display',
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),

                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: () {
                                final rawAction = (doc['action'] ?? '')
                                    .toString();
                                final hasTimeOff = rawAction.isNotEmpty;

                                final isGuest =
                                    _authService.currentUser?.isAnonymous ??
                                    false;
                                if (isGuest) {
                                  showGuestRestrictionDialog(context);
                                  return;
                                }
                                if (hasTimeOff) {
                                  _showTimeOffDataDialog(context, doc, index);
                                  return;
                                }
                                if (widget.onAssignTimeOff != null) {
                                  widget.onAssignTimeOff!(doc);
                                } else {
                                  Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              AssignTimeOffScreen(
                                                onBack: () =>
                                                    Navigator.of(context).pop(),
                                                initialWorker: doc,
                                              ),
                                        ),
                                      )
                                      .then((_) {
                                        if (!isGuest) return;
                                        _refreshGuestData();
                                      });
                                }
                              },
                              mouseCursor: SystemMouseCursors.click,
                              borderRadius: BorderRadius.circular(6),
                              splashColor: const Color(
                                0xFF0D4CC6,
                              ).withValues(alpha: 0.15),
                              highlightColor: const Color(
                                0xFF0D4CC6,
                              ).withValues(alpha: 0.05),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        action,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: hasTimeOff
                                              ? const Color(0xFF4AC000)
                                              : const Color(0xFF0D4CC6),
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTimeOffDataDialog(
    BuildContext context,
    Map<String, dynamic> data,
    int index,
  ) async {
    final String name = (data['name'] ?? '').toString();
    final String email = (data['email'] ?? '').toString();
    final String action = (data['action'] ?? '').toString();
    final selectedDates = TimeOffService.selectedDatesForRecord(data);
    final String selectedDatesText = selectedDates
        .map((date) => DateFormat('dd/MM/yyyy').format(date))
        .join(', ');
    final String selectedDays = (data['requestedDays'] ?? selectedDates.length)
        .toString();
    final String notes = (data['notes'] ?? '').toString();
    final String remainingLeaves = (data['remainingLeaves'] ?? '0').toString();
    final String annualLeavesBalance =
        (data['availableAnnualLeaves'] ?? data['annualLeaves'] ?? '0')
            .toString();

    String localizedAction = action;
    if (action == 'Annual Leave') {
      localizedAction = 'annual_leave'.tr();
    } else if (action == 'Sick Leave') {
      localizedAction = 'sick_leave_type'.tr();
    } else if (action == 'Casual Leave') {
      localizedAction = 'casual_leave_type'.tr();
    } else if (action == 'Medical Leave') {
      localizedAction = 'medical_leave_type'.tr();
    } else if (action == 'Maternity Leave') {
      localizedAction = 'maternity_leave'.tr();
    } else if (action == 'Custom Leave') {
      localizedAction = 'custom_leave_type'.tr();
    } else if (action == 'Unpaid Leave') {
      localizedAction = 'unpaid_leave_type'.tr();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth * 0.9 : 480.0;

    final result = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: Container(
            width: dialogWidth,
            height: 430,
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
                  height: 40,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF004FDE),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // ── Close icon (left) ──
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: Color(0xFFFFFFFF),
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Title (center) ──
                      Expanded(
                        child: Text(
                          'assign_time_off'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Edit icon (right) ──
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop('edit'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: SvgPicture.asset(
                              'assets/edit_icon.svg',
                              height: 22,
                              width: 22,
                              colorFilter: const ColorFilter.mode(
                                Color(0xFFFFFFFF),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildWorkerPreviewHeader(
                  name: name,
                  email: email,
                  imageUrl: data['profileImage']?.toString(),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      border: Border(
                        left: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        right: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        bottom: BorderSide(
                          color: Color(0xFFE8E8E8),
                          width: 1.5,
                        ),
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimeOffMetricCard(
                                  icon: const Icon(
                                    Icons.event_note,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'time_off_type'.tr(),
                                  value: localizedAction,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTimeOffMetricCard(
                                  icon: const Icon(
                                    Icons.event_available,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'selected_days'.tr(),
                                  value: selectedDays,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimeOffMetricCard(
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'selected_dates'.tr(),
                                  value: selectedDatesText,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTimeOffMetricCard(
                                  icon: const Icon(
                                    Icons.beach_access,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'remaining_days'.tr(),
                                  value: remainingLeaves,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimeOffMetricCard(
                                  icon: const Icon(
                                    Icons.notes,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'notes_label'.tr(),
                                  value: notes.isNotEmpty ? notes : '-',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTimeOffMetricCard(
                                  icon: const Icon(
                                    Icons.event_available,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'annual_leaves'.tr(),
                                  value: annualLeavesBalance,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == 'edit' && mounted) {
      setState(() {
        _isAssigningTimeOff = true;
        _workerForTimeOff = data;
      });
    }
  }

  Widget _buildWorkerPreviewHeader({
    required String name,
    required String email,
    String? imageUrl,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 16, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          WorkerAvatar(
            imageUrl: imageUrl,
            name: name,
            size: 60,
            border: Border.all(color: const Color(0xFF0A51D0), width: 2),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/email.svg',
                      height: 12,
                      width: 12,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF666666),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          fontFamily: 'SF Pro Display',
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeOffMetricCard({
    required Widget icon,
    required String title,
    required String value,
  }) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EEFC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: icon),
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
                  overflow: TextOverflow.ellipsis,
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
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    double dynamicHeight = MediaQuery.of(context).size.height - 450;
    if (dynamicHeight < 300) dynamicHeight = 300;
    return SizedBox(
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
              'no_time_off_records'.tr(),
              style: TextStyle(
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
  }
}
