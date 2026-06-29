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
  String _searchQuery = '';
  String _selectedTab = 'All';
  List<Map<String, dynamic>> _timeoffDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  bool _isLoading = true;
  int _currentPage = 1;
  static const int _itemsPerPage = 8;
  StreamSubscription? _timeoffSub;
  StreamSubscription? _workersSub;

  @override
  void dispose() {
    _timeoffSub?.cancel();
    _workersSub?.cancel();
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
          ...timeoffRecord,
          'profileImage':
              worker['profileImage'] ?? timeoffRecord['profileImage'],
          'phone': worker['phone'] ?? timeoffRecord['phone'] ?? '',
          'contact': worker['phone'] ?? timeoffRecord['contact'] ?? '',
        });
      } else {
        // Include workers without timeoff records with default empty values
        combined.add({
          'id': worker['id'] ?? '',
          'name': worker['name'] ?? '',
          'email': worker['email'] ?? '',
          'position': worker['position'] ?? '',
          'phone': worker['phone'] ?? '',
          'contact': worker['phone'] ?? '',
          'profileImage': worker['profileImage'] ?? '',
          'action': '',
          'startDate': '',
          'endDate': '',
          'requestedDays': 0,
        });
      }
    }

    _timeoffDocs = combined;
    _isLoading = false;
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
      return pos.contains('designer') &&
          !pos.contains('engineer') &&
          !pos.contains('developer');
    } else if (f == 'developer') {
      return (pos.contains('developer') || pos.contains('development')) &&
          !pos.contains('designer');
    } else if (f == 'engineering') {
      return (pos.contains('engineer') ||
              pos.contains('architect') ||
              pos.contains('analyst') ||
              pos.contains('scientist')) &&
          !pos.contains('designer') &&
          !pos.contains('developer');
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
    return _timeoffDocs.where((doc) {
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
            localizedAction = 'annual_leave'.tr();
          } else if (action == 'Sick Leave') {
            localizedAction = 'sick_leave_type'.tr();
          } else if (action == 'Casual Leave') {
            localizedAction = 'casual_leave_type'.tr();
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
                  Text(
                    'time_off_list'.tr(),
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
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _currentPage = 1;
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
                setState(() {
                  _searchQuery = '';
                  _currentPage = 1;
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabItem('All', 'all_filter'.tr()),
          _buildTabItem('Designer', 'designer'.tr()),
          _buildTabItem('Developer', 'developer'.tr()),
          _buildTabItem('Engineering', 'engineering'.tr()),
          _buildTabItem('Sales', 'sales'.tr()),
          _buildTabItem('Management', 'management'.tr()),
        ],
      ),
    );
  }

  Widget _buildTabItem(String filterKey, String displayLabel) {
    final bool isSelected = _selectedTab == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = filterKey;
          _currentPage = 1;
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
          displayLabel,
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
    final totalPages = (workers.isEmpty)
        ? 1
        : (workers.length / _itemsPerPage).ceil();
    final safeStartIndex = (_currentPage - 1) * _itemsPerPage >= workers.length
        ? 0
        : (_currentPage - 1) * _itemsPerPage;
    final paginatedWorkers = workers.isEmpty
        ? <Map<String, dynamic>>[]
        : workers.sublist(
            safeStartIndex,
            (safeStartIndex + _itemsPerPage) > workers.length
                ? workers.length
                : (safeStartIndex + _itemsPerPage),
          );

    final double tableHeight = (MediaQuery.of(context).size.height - 339).clamp(
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
              itemCount: paginatedWorkers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = paginatedWorkers[index];
                final name = (doc['name'] ?? '').toString();
                final email = (doc['email'] ?? '').toString();
                final position = (doc['position'] ?? '').toString();
                final contact = (doc['contact'] ?? doc['phone'] ?? '')
                    .toString();
                String action = (doc['action'] ?? '').toString();
                if (action == 'Annual Leave') {
                  action = 'annual_leave'.tr();
                } else if (action == 'Sick Leave') {
                  action = 'sick_leave_type'.tr();
                } else if (action == 'Casual Leave') {
                  action = 'casual_leave_type'.tr();
                } else if (action == 'Maternity Leave') {
                  action = 'maternity_leave'.tr();
                } else if (action.isEmpty) {
                  action = 'no_time_off'.tr();
                }
                return Tooltip(
                  message: 'long_press_to_delete'.tr(),
                  child: GestureDetector(
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
                                        Tooltip(
                                          message: name,
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Color(0xFF000000),
                                              fontFamily: 'SF Pro Display',
                                            ),
                                            maxLines: 2,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
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
                          // Position
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 24.0),
                              child: Tooltip(
                                message: position,
                                child: Text(
                                  position,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  maxLines: 2,
                                ),
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
                                  if (widget.onAssignTimeOff != null) {
                                    widget.onAssignTimeOff!(doc);
                                  } else {
                                    // Fallback if rendered as standalone
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AssignTimeOffScreen(
                                              onBack: () =>
                                                  Navigator.of(context).pop(),
                                              initialWorker: doc,
                                            ),
                                      ),
                                    );
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
                                    child: Text(
                                      action,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Color(0xFF0D4CC6),
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
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
                    Icons.chevron_left,
                    color: _currentPage > 1
                        ? Colors.black
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_right,
                    color: _currentPage < totalPages
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
