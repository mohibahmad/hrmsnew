import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/snackbar_utils.dart';
import '../utils/image_utils.dart';
import '../widgets/notification_bell.dart';

import 'assign_time_off.dart';

class Worker {
  final String name;
  final String email;
  final String position;
  final String contact;
  final String action;
  final bool
  isMaleAvatar; // Used to mock the specific placeholder illustrations

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
  List<Map<String, dynamic>> _timeoffDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  bool _isLoading = true;

  static const _defaultFilters = [
    'All',
    'Designer',
    'Developer',
    'Engineering',
    'Sales',
    'Management',
  ];
  StreamSubscription? _timeoffSub;
  StreamSubscription? _workersSub;

  bool _isAssigningTimeOff = false;
  Map<String, dynamic>? _workerForTimeOff;

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
    for (var worker in _workersList) {
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final name = (worker['name'] ?? '').toString().trim().toLowerCase();

      final timeoffRecord = _timeoffDocs.firstWhere((t) {
        final tEmail = (t['email'] ?? '').toString().trim().toLowerCase();
        final tName = (t['name'] ?? '').toString().trim().toLowerCase();
        return (email.isNotEmpty && tEmail == email) ||
            (name.isNotEmpty && tName == name);
      }, orElse: () => {});

      if (timeoffRecord.isNotEmpty) {
        combined.add({
          ...worker,
          ...timeoffRecord,
          'profileImage':
              worker['profileImage'] ?? timeoffRecord['profileImage'],
          'phone': worker['phone'] ?? timeoffRecord['phone'] ?? '',
          'contact': worker['phone'] ?? timeoffRecord['contact'] ?? '',
        });
      } else {
        // Include workers without timeoff records with default empty values
        combined.add({
          ...worker,
          'action': '',
          'startDate': '',
          'endDate': '',
          'requestedDays': 0,
        });
      }
    }

    // 🔥 FIX: Calculate remaining leaves for each worker
    for (var doc in combined) {
      final annualLeaves =
          int.tryParse(doc['annualLeaves']?.toString() ?? '0') ?? 0;
      final usedLeaves =
          int.tryParse(doc['leavesUsed']?.toString() ?? '0') ?? 0;
      final remaining = annualLeaves - usedLeaves;
      doc['remainingLeaves'] = remaining.toString();
    }

    _timeoffDocs = combined;
    _isLoading = false;
  }

  void _refreshGuestData() {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _isLoading = true;
        _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
        _timeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _combineTimeOff();
      });
    } else {
      _isLoading = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _timeoffDocs = [];
    _workersList = [];
    _isLoading = true;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = FirestoreService().workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workersList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _combineTimeOff();
          });
        }
      });
      _timeoffSub = FirestoreService().timeoffStream.listen(
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
              _timeoffDocs = sortedList;
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
      _timeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
      _combineTimeOff();
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
    return pos.contains(f) || f.contains(pos);
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

    // Sort: Workers with assigned time off at top, then without
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
    // Don't allow deletion of workers without timeoff records
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
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      if (isGuest) {
        setState(() {
          DummyData.timeoff.removeWhere(
            (e) =>
                e['id'] == doc['id'] &&
                e['name'] == doc['name'] &&
                e['action'] == doc['action'],
          );
          DummyData.saveToPrefs();
          _timeoffDocs.removeWhere(
            (e) =>
                e['id'] == doc['id'] &&
                e['name'] == doc['name'] &&
                e['action'] == doc['action'],
          );
          // Refresh remaining leaves
          _combineTimeOff();
        });
      } else {
        final id = doc['id'] as String?;
        if (id != null && id.isNotEmpty) {
          await FirestoreService().deleteTimeOffRecord(id);
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
                  const SizedBox(height: 10),
                  Text(
                    'time_off_list'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 15),

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
          // Notification Bell
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

  List<String> get _extraPositions {
    final existing = _defaultFilters.map((e) => e.toLowerCase()).toSet();
    final extras = <String>{};
    for (final doc in _workersList) {
      final pos = (doc['position'] ?? '').toString().trim();
      if (pos.isNotEmpty && !existing.contains(pos.toLowerCase())) {
        extras.add(pos);
      }
    }
    final sorted = extras.toList()..sort();
    return sorted;
  }

  Widget _buildFilterTabs() {
    return Container(
      width: 550,
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
            _buildTabItem('All', 'all_filter'.tr()),
            Container(
              width: 1,
              height: 38,
              color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
            ),
            if (_workersList.isEmpty) ...[
              _buildTabItem('Designer', 'designer'.tr()),
              Container(
                width: 1,
                height: 38,
                color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
              ),
              _buildTabItem('Developer', 'developer'.tr()),
              Container(
                width: 1,
                height: 38,
                color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
              ),
              _buildTabItem('Engineering', 'engineering'.tr()),
              Container(
                width: 1,
                height: 38,
                color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
              ),
              _buildTabItem('Sales', 'sales'.tr()),
              Container(
                width: 1,
                height: 38,
                color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
              ),
              _buildTabItem('Management', 'management'.tr()),
            ] else ...[
              ..._extraPositions.asMap().entries.expand(
                (entry) => [
                  if (entry.key > 0)
                    Container(
                      width: 1,
                      height: 38,
                      color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
                    ),
                  _buildTabItem(entry.value, entry.value),
                ],
              ),
            ],
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
    final double tableHeight = (MediaQuery.of(context).size.height - 339).clamp(
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
          // Table Header
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
          // Table Rows
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
                        // Worker Name with Avatar
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 24.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundImage: getProfileImage(
                                    doc['profileImage']?.toString(),
                                    doc['email']?.toString(),
                                    index,
                                  ),
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
                                          fontWeight: FontWeight.bold,
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
                                          fontSize: 17,
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
                        // Position
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
                        // Contact
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
                        // Time Off Action
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: () {
                                final rawAction = (doc['action'] ?? '')
                                    .toString();
                                final hasTimeOff = rawAction.isNotEmpty;

                                if (hasTimeOff) {
                                  _showTimeOffDataDialog(context, doc, index);
                                  return;
                                }

                                final isGuest =
                                    AuthService().currentUser?.isAnonymous ??
                                    false;
                                if (isGuest) {
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
                                      .then((_) => _refreshGuestData());
                                  return;
                                }
                                if (widget.onAssignTimeOff != null) {
                                  widget.onAssignTimeOff!(doc);
                                } else {
                                  // Fallback if rendered as standalone
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
                                      .then((_) => _refreshGuestData());
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
                                          fontSize: 17,
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
    final String contact = (data['contact'] ?? data['phone'] ?? '').toString();
    final String action = (data['action'] ?? '').toString();
    final String startDate = (data['startDate'] ?? '').toString();
    final String endDate = (data['endDate'] ?? '').toString();
    final String notes = (data['notes'] ?? '').toString();
    final String remainingLeaves = (data['remainingLeaves'] ?? '0').toString();

    String localizedAction = action;
    if (action == 'Annual Leave') {
      localizedAction = 'annual_leave'.tr();
    } else if (action == 'Sick Leave') {
      localizedAction = 'sick_leave_type'.tr();
    } else if (action == 'Casual Leave') {
      localizedAction = 'casual_leave_type'.tr();
    } else if (action == 'Maternity Leave') {
      localizedAction = 'maternity_leave'.tr();
    } else if (action == 'Custom Leave') {
      localizedAction = 'custom_leave_type'.tr();
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
            height: 520,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Icon(
                            Icons.close,
                            color: Color(0xFFFFFFFF),
                            size: 24,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          'assign_time_off'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop('edit'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SvgPicture.asset(
                            'assets/edit_icon.svg',
                            height: 20,
                            width: 20,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFFFFFFFF),
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFFFFFFFF),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0A51D0),
                            width: 2,
                          ),
                          image: DecorationImage(
                            image: getProfileImage(
                              data['profileImage']?.toString(),
                              data['email']?.toString(),
                              index,
                            ),
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
                            Text(
                              name,
                              style: const TextStyle(
                                color: Color(0xFF333333),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SF Pro Display',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.mail_outline,
                                  color: Color(0xFF666666),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    email,
                                    style: const TextStyle(
                                      color: Color(0xFF666666),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.phone,
                                    color: Color(0xFF666666),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    contact,
                                    style: const TextStyle(
                                      color: Color(0xFF666666),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    overflow: TextOverflow.ellipsis,
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
                                    Icons.calendar_today,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'start_date'.tr(),
                                  value: startDate,
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
                                  title: 'end_date'.tr(),
                                  value: endDate,
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
                                  value: remainingLeaves,
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
    return Container(
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
