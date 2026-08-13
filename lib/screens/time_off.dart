import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/error_reporter.dart';
import '../services/dummy_data.dart';
import '../services/time_off_service.dart';
import '../utils/file_utils.dart';
import '../widgets/notification_bell.dart';

import 'assign_time_off.dart';
import '../utils/guest_restriction.dart';
import '../utils/localization_helper.dart';
import '../utils/ui_utils.dart';
import '../services/attendance_report_service.dart';
import '../services/time_off_export_service.dart';
import '../utils/date_time_utils.dart';

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

class TimeOffScreen extends ConsumerStatefulWidget {
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
  ConsumerState<TimeOffScreen> createState() => _TimeOffScreenState();
}

class _TimeOffScreenState extends ConsumerState<TimeOffScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTab = 'All';
  String _recordsPeriodFilter = 'All Time';
  DateTimeRange? _customDateRange;
  String _recordsLeaveTypeFilter = 'All';

  List<Map<String, dynamic>> get _filteredTimeOffRecords {
    final query = _searchQuery.trim().toLowerCase();

    return _rawTimeoffDocs.where((record) {
      if (query.isNotEmpty) {
        final workerName =
            (record['workerName'] ??
                    record['name'] ??
                    record['email'] ??
                    record['workerEmail'] ??
                    '')
                .toString()
                .toLowerCase();
        if (!workerName.contains(query)) return false;
      }

      if (_recordsLeaveTypeFilter != 'All') {
        final rawType = (record['leaveType'] ?? record['type'] ?? '')
            .toString();
        final normType = TimeOffService.normalizeLeaveType(rawType);
        final normSelected = TimeOffService.normalizeLeaveType(
          _recordsLeaveTypeFilter,
        );
        if (normType != normSelected) return false;
      }

      final recordDate = AppDateUtils.dateFromValue(
        record['startDate'] ?? record['date'],
      );
      if (recordDate == null) return true;

      final recordDay = DateTime(
        recordDate.year,
        recordDate.month,
        recordDate.day,
      );

      if (_recordsPeriodFilter == 'Custom Range') {
        if (_customDateRange != null) {
          final start = DateTime(
            _customDateRange!.start.year,
            _customDateRange!.start.month,
            _customDateRange!.start.day,
          );
          final end = DateTime(
            _customDateRange!.end.year,
            _customDateRange!.end.month,
            _customDateRange!.end.day,
            23,
            59,
            59,
          );
          if (recordDay.isBefore(start) || recordDay.isAfter(end)) return false;
        }
      } else if (_recordsPeriodFilter != 'All Time') {
        final range = AttendanceReportService.rangeForPeriod(
          _recordsPeriodFilter,
        );
        if (!range.contains(recordDay)) return false;
      }

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _rawTimeoffDocs = [];
  List<Map<String, dynamic>> _timeoffDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  bool _isLoading = true;
  bool _isExportingCsv = false;
  bool _workersLoaded = false;
  bool _timeoffLoaded = false;
  bool _workersLoadFailed = false;
  bool _timeoffLoadFailed = false;

  StreamSubscription? _timeoffSub;
  StreamSubscription? _workersSub;

  bool _isAssigningTimeOff = false;
  Map<String, dynamic>? _workerForTimeOff;
  late AuthService _authService;
  late FirestoreService _firestore;
  late bool _isGuestMode;

  @override
  void dispose() {
    _timeoffSub?.cancel();
    _workersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _l(String key, String fallback) {
    final translated = key.tr().trim();
    return translated.isEmpty || translated == key ? fallback : translated;
  }

  String _normalizedValue(dynamic value) =>
      (value ?? '').toString().trim().toLowerCase();

  String _localizedLeaveType(String type) {
    return switch (TimeOffService.normalizeLeaveType(type)) {
      'Annual Leave' => 'annual_leave'.tr(),
      'Sick Leave' => 'sick_leave_type'.tr(),
      'Casual Leave' => 'casual_leave_type'.tr(),
      'Medical Leave' => 'medical_leave_type'.tr(),
      _ => type,
    };
  }

  bool _isAttendanceManagedTimeOff(Map<String, dynamic> record) {
    return (record['source'] ?? '').toString().trim().toLowerCase() ==
        'attendance';
  }

  String _firstNonEmptyValue(Iterable<dynamic> values) {
    for (final value in values) {
      final normalized = (value ?? '').toString().trim();
      if (normalized.isNotEmpty && normalized.toLowerCase() != 'null') {
        return normalized;
      }
    }
    return '';
  }

  bool _hasUniqueWorkerName(String normalizedName) {
    if (normalizedName.isEmpty) return false;
    var matches = 0;
    for (final worker in _workersList) {
      if (_normalizedValue(worker['name']) == normalizedName) {
        matches++;
        if (matches > 1) return false;
      }
    }
    return matches == 1;
  }

  int _remainingPaidLeaveForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> workerRecords,
  ) {
    final total = TimeOffService.configuredPaidLeaveAllowance(worker);
    final used = TimeOffService.paidDaysUsedForWorker(worker, workerRecords);
    return (total - used).clamp(0, total).toInt();
  }

  Map<String, dynamic> _docForNewLeave(Map<String, dynamic> doc) {
    return {...doc}
      ..remove('action')
      ..remove('type')
      ..remove('selectedDates')
      ..remove('startDate')
      ..remove('endDate')
      ..remove('notes')
      ..remove('status')
      ..remove('requestedDays');
  }

  bool _canAssignTimeOff(Map<String, dynamic> worker) {
    final status =
        (worker['employmentStatus'] ??
                worker['workerStatus'] ??
                worker['status'] ??
                'Active')
            .toString()
            .trim()
            .toLowerCase();
    return !const {
      'inactive',
      'terminated',
      'deleted',
      'archived',
    }.contains(status);
  }

  int _compareTimeOffRows(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstHasRecord = (first['action'] ?? '').toString().isNotEmpty;
    final secondHasRecord = (second['action'] ?? '').toString().isNotEmpty;
    if (firstHasRecord != secondHasRecord) {
      return firstHasRecord ? -1 : 1;
    }

    final firstStart = TimeOffService.parseDate(first['startDate']);
    final secondStart = TimeOffService.parseDate(second['startDate']);
    if (firstStart != null && secondStart != null) {
      final byStartDate = secondStart.compareTo(firstStart);
      if (byStartDate != 0) return byStartDate;
    } else if (firstStart != null) {
      return -1;
    } else if (secondStart != null) {
      return 1;
    }

    final byName = _normalizedValue(
      first['name'],
    ).compareTo(_normalizedValue(second['name']));
    if (byName != 0) return byName;

    return (first['id'] ?? '').toString().compareTo(
      (second['id'] ?? '').toString(),
    );
  }

  void _combineGuestTimeOff() {
    if (_workersList.isEmpty) {
      _timeoffDocs = [];
      _isLoading = false;
      return;
    }

    final combined = <Map<String, dynamic>>[];
    for (final worker in _workersList) {
      final workerId = (worker['id'] ?? '').toString().trim();
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final name = (worker['name'] ?? '').toString().trim().toLowerCase();
      final matchingRecords = _rawTimeoffDocs.where((record) {
        if (!TimeOffService.isActiveRecord(record)) return false;
        if (_isAttendanceManagedTimeOff(record)) return false;
        final recordWorkerId = (record['workerId'] ?? '').toString().trim();
        final tEmail = (record['email'] ?? '').toString().trim().toLowerCase();
        final tName = (record['name'] ?? record['workerName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return (workerId.isNotEmpty &&
                recordWorkerId.isNotEmpty &&
                workerId == recordWorkerId) ||
            (recordWorkerId.isEmpty && email.isNotEmpty && tEmail == email) ||
            (email.isEmpty && name.isNotEmpty && tName == name);
      }).toList();

      final balanceRecords = _rawTimeoffDocs.where((record) {
        if (!TimeOffService.isActiveRecord(record)) return false;
        final recordWorkerId = (record['workerId'] ?? '').toString().trim();
        final tEmail = (record['email'] ?? '').toString().trim().toLowerCase();
        final tName = (record['name'] ?? record['workerName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return (workerId.isNotEmpty &&
                recordWorkerId.isNotEmpty &&
                workerId == recordWorkerId) ||
            (recordWorkerId.isEmpty && email.isNotEmpty && tEmail == email) ||
            (email.isEmpty && name.isNotEmpty && tName == name);
      }).toList();
      final remaining = TimeOffService.remainingPaidLeave(
        worker,
        balanceRecords,
      );

      if (matchingRecords.isEmpty) {
        combined.add({
          ...worker,
          'action': '',
          'startDate': '',
          'endDate': '',
          'requestedDays': 0,
          'annualLeaves': worker['annualLeaves'],
          'availableAnnualLeaves': worker['availableAnnualLeaves'],
          'remainingLeaves': remaining.toString(),
        });
        continue;
      }

      final sortedRecords = List<Map<String, dynamic>>.from(matchingRecords)
        ..sort((a, b) {
          final aStart = TimeOffService.parseDate(a['startDate']);
          final bStart = TimeOffService.parseDate(b['startDate']);
          if (aStart == null && bStart == null) return 0;
          if (aStart == null) return 1;
          if (bStart == null) return -1;
          return bStart.compareTo(aStart);
        });
      final timeoffRecord = sortedRecords.first;
      combined.add({
        ...worker,
        ...timeoffRecord,
        'workerId': worker['id'],
        'action': TimeOffService.leaveType(timeoffRecord),
        'type': TimeOffService.leaveType(timeoffRecord),
        'name': worker['name'] ?? timeoffRecord['name'],
        'email': worker['email'] ?? timeoffRecord['email'],
        'profileImage': worker['profileImage'] ?? timeoffRecord['profileImage'],
        'phone': worker['phone'] ?? timeoffRecord['phone'] ?? '',
        'contact': worker['phone'] ?? timeoffRecord['contact'] ?? '',
        'annualLeaves': worker['annualLeaves'],
        'availableAnnualLeaves': worker['availableAnnualLeaves'],
        'remainingLeaves': remaining.toString(),
      });
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

  void _combineTimeOff() {
    if (_isGuestMode) {
      _combineGuestTimeOff();
      return;
    }

    if (!_workersLoaded || !_timeoffLoaded) {
      _isLoading = true;
      return;
    }

    if (_workersLoadFailed || _timeoffLoadFailed) {
      _timeoffDocs = [];
      _isLoading = false;
      return;
    }

    if (_workersList.isEmpty) {
      _timeoffDocs = [];
      _isLoading = false;
      return;
    }

    final recordsByWorkerId = <String, List<Map<String, dynamic>>>{};
    final legacyRecordsByEmail = <String, List<Map<String, dynamic>>>{};
    final allRecordsByWorkerId = <String, List<Map<String, dynamic>>>{};
    final allLegacyRecordsByEmail = <String, List<Map<String, dynamic>>>{};

    for (final record in _rawTimeoffDocs) {
      if (!TimeOffService.isActiveRecord(record)) continue;

      final workerId = (record['workerId'] ?? '').toString().trim();
      final email = _normalizedValue(record['email']);
      final isAttendanceManaged = _isAttendanceManagedTimeOff(record);

      if (workerId.isNotEmpty) {
        allRecordsByWorkerId.putIfAbsent(workerId, () => []).add(record);
        if (!isAttendanceManaged) {
          recordsByWorkerId.putIfAbsent(workerId, () => []).add(record);
        }
      } else if (email.isNotEmpty) {
        allLegacyRecordsByEmail.putIfAbsent(email, () => []).add(record);
        if (!isAttendanceManaged) {
          legacyRecordsByEmail.putIfAbsent(email, () => []).add(record);
        }
      }
    }

    final combined = <Map<String, dynamic>>[];
    for (final worker in _workersList) {
      final workerId = (worker['id'] ?? '').toString().trim();
      final email = _normalizedValue(worker['email']);
      final name = _normalizedValue(worker['name']);
      final canUseNameFallback = email.isEmpty && _hasUniqueWorkerName(name);

      List<Map<String, dynamic>> matchingRecords;
      List<Map<String, dynamic>> balanceRecords;
      if (workerId.isNotEmpty) {
        matchingRecords = recordsByWorkerId[workerId] ?? const [];
        balanceRecords = allRecordsByWorkerId[workerId] ?? const [];
      } else if (email.isNotEmpty) {
        matchingRecords = legacyRecordsByEmail[email] ?? const [];
        balanceRecords = allLegacyRecordsByEmail[email] ?? const [];
      } else {
        balanceRecords = _rawTimeoffDocs.where((record) {
          if (!TimeOffService.isActiveRecord(record)) return false;
          final recordWorkerId = (record['workerId'] ?? '').toString().trim();
          if (recordWorkerId.isNotEmpty) return false;
          final recordEmail = _normalizedValue(record['email']);
          if (recordEmail.isNotEmpty) return false;
          final recordName = _normalizedValue(
            record['name'] ?? record['workerName'],
          );
          return canUseNameFallback && name.isNotEmpty && recordName == name;
        }).toList();
        matchingRecords = balanceRecords
            .where((record) => !_isAttendanceManagedTimeOff(record))
            .toList();
      }

      final remaining = _remainingPaidLeaveForWorker(worker, balanceRecords);

      if (matchingRecords.isEmpty) {
        combined.add({
          ...worker,
          'workerId': workerId,
          'action': '',
          'startDate': '',
          'endDate': '',
          'requestedDays': 0,
          'annualLeaves': worker['annualLeaves'],
          'availableAnnualLeaves': worker['availableAnnualLeaves'],
          'remainingLeaves': remaining.toString(),

          'canAssignTimeOff': _canAssignTimeOff(worker),
        });
        continue;
      }

      final sortedRecords = List<Map<String, dynamic>>.from(matchingRecords)
        ..sort((a, b) {
          final aStart = TimeOffService.parseDate(a['startDate']);
          final bStart = TimeOffService.parseDate(b['startDate']);
          if (aStart == null && bStart == null) return 0;
          if (aStart == null) return 1;
          if (bStart == null) return -1;
          return bStart.compareTo(aStart);
        });
      final timeoffRecord = sortedRecords.first;
      final phone = _firstNonEmptyValue([
        worker['phone'],
        worker['contact'],
        timeoffRecord['phone'],
        timeoffRecord['contact'],
      ]);
      combined.add({
        ...worker,
        ...timeoffRecord,
        'workerId': workerId.isNotEmpty
            ? workerId
            : (timeoffRecord['workerId'] ?? '').toString(),
        'action': TimeOffService.leaveType(timeoffRecord),
        'type': TimeOffService.leaveType(timeoffRecord),
        'name': _firstNonEmptyValue([
          worker['name'],
          timeoffRecord['name'],
          timeoffRecord['workerName'],
        ]),
        'email': _firstNonEmptyValue([worker['email'], timeoffRecord['email']]),
        'profileImage': _firstNonEmptyValue([
          worker['profileImage'],
          timeoffRecord['profileImage'],
          timeoffRecord['workerAvatar'],
        ]),
        'phone': phone,
        'contact': phone,
        'annualLeaves': worker['annualLeaves'],
        'availableAnnualLeaves': worker['availableAnnualLeaves'],
        'remainingLeaves': remaining.toString(),
        'canAssignTimeOff': _canAssignTimeOff(worker),
      });
    }

    combined.sort(_compareTimeOffRows);
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
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    _rawTimeoffDocs = [];
    _timeoffDocs = [];
    _workersList = [];
    _isLoading = true;
    _isGuestMode = _authService.currentUser?.isAnonymous ?? false;

    if (!_isGuestMode) {
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (!mounted) return;
          setState(() {
            _workersList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _workersLoaded = true;
            _workersLoadFailed = false;
            _combineTimeOff();
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'timeOffWorkersStream',
          );
          if (!mounted) return;
          setState(() {
            _workersList = [];
            _workersLoaded = true;
            _workersLoadFailed = true;
            _combineTimeOff();
          });
        },
      );

      _timeoffSub = _firestore.timeoffStream.listen(
        (snapshot) {
          if (!mounted) return;
          setState(() {
            final sortedList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            sortedList.sort((a, b) {
              final aTime = a['createdAt'];
              final bTime = b['createdAt'];
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              if (aTime is Timestamp && bTime is Timestamp) {
                return bTime.compareTo(aTime);
              }
              return 0;
            });
            _rawTimeoffDocs = sortedList;
            _timeoffLoaded = true;
            _timeoffLoadFailed = false;
            _combineTimeOff();
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'timeOffRecordsStream',
          );
          if (!mounted) return;
          setState(() {
            _rawTimeoffDocs = [];
            _timeoffLoaded = true;
            _timeoffLoadFailed = true;
            _combineTimeOff();
          });
        },
      );
    } else {
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
      _workersLoaded = true;
      _timeoffLoaded = true;
      _combineTimeOff();
    }
  }

  bool _matchesFilter(String position, String filter) {
    if (filter == 'All') return true;
    return position.toLowerCase().contains(filter.toLowerCase());
  }

  bool get _isDropdownFilterActive {
    return _recordsPeriodFilter != 'All Time' ||
        _recordsLeaveTypeFilter != 'All';
  }

  List<Map<String, dynamic>> get _matchingWorkersForDropdownFilters {
    final base = _filteredWorkers;
    if (!_isDropdownFilterActive) return base;

    return base.where((worker) {
      final workerId = (worker['id'] ?? worker['workerId'] ?? '')
          .toString()
          .trim();
      final workerEmail = (worker['email'] ?? worker['workerEmail'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return _filteredTimeOffRecords.any((rec) {
        final recId = (rec['workerId'] ?? rec['id'] ?? '').toString().trim();
        final recEmail = (rec['workerEmail'] ?? rec['email'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return (workerId.isNotEmpty && recId.isNotEmpty && recId == workerId) ||
            (workerEmail.isNotEmpty &&
                recEmail.isNotEmpty &&
                recEmail == workerEmail);
      });
    }).toList();
  }

  List<Map<String, dynamic>> get _displayWorkers {
    if (!_isDropdownFilterActive) return _filteredWorkers;
    return _matchingWorkersForDropdownFilters;
  }

  String get _activeFilterName {
    final List<String> parts = [];
    if (_recordsLeaveTypeFilter != 'All') {
      parts.add(_localizedLeaveType(_recordsLeaveTypeFilter));
    }
    if (_recordsPeriodFilter != 'All Time') {
      if (_recordsPeriodFilter == 'Custom Range' && _customDateRange != null) {
        final start = _customDateRange!.start;
        final end = _customDateRange!.end;
        if (start.year == end.year &&
            start.month == end.month &&
            start.day == end.day) {
          parts.add(DateFormat('dd MMM').format(start));
        } else {
          parts.add(
            '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM').format(end)}',
          );
        }
      } else {
        final periodOptions = [
          {'value': 'All Time', 'label': _l('all_time', 'All Time')},
          {'value': 'This Month', 'label': _l('this_month', 'This Month')},
          {
            'value': 'Last 6 Months',
            'label': _l('last_6_months', 'Last 6 Months'),
          },
          {'value': 'This Year', 'label': _l('this_year', 'This Year')},
          {
            'value': 'Custom Range',
            'label': _l('custom_range', 'Custom Range'),
          },
        ];
        final match = periodOptions.firstWhere(
          (e) => e['value'] == _recordsPeriodFilter,
          orElse: () => {
            'value': _recordsPeriodFilter,
            'label': _recordsPeriodFilter,
          },
        );
        parts.add(match['label']!);
      }
    }
    return parts.join(' • ');
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final filtered = _timeoffDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final position = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      final matchesSearch = name.contains(query) || position.contains(query);
      if (!matchesSearch) return false;

      final matchesTab = _matchesFilter(position, _selectedTab);
      if (!matchesTab) return false;

      return true;
    }).toList();

    if (_isGuestMode) {
      filtered.sort((a, b) {
        final actionA = (a['action'] ?? '').toString();
        final actionB = (b['action'] ?? '').toString();
        if (actionA.isNotEmpty && actionB.isEmpty) return -1;
        if (actionA.isEmpty && actionB.isNotEmpty) return 1;
        return 0;
      });
    } else {
      filtered.sort(_compareTimeOffRows);
    }

    return filtered;
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

    final filtered = _displayWorkers;

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
                  const SizedBox(height: 12),
                  _buildFilterTabs(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'time_off_list'.tr(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      _buildRecordsFiltersAndExportRow(),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                hintText: 'search_workers_name_position'.tr(),
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
    const defaultPositions = LocalizationHelper.defaultJobPositions;
    final actualPositions = <String>{};
    final positionNormalizer = <String, String>{};
    for (final w in _workersList) {
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

    final allFilters = ['All', ...positionsToShow];

    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final f in allFilters)
              _buildTabItem(
                f,
                f == 'All'
                    ? 'all_filter'.tr()
                    : LocalizationHelper.localizePosition(f),
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0247C4) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          maxLines: 1,
          softWrap: false,
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
                final bool isLimitReached = TimeOffService.isWorkerLimitReached(
                  doc,
                  _rawTimeoffDocs,
                );

                final bool canAssign = doc['canAssignTimeOff'] != false;
                final String displayAction = !canAssign
                    ? (doc['status'] ??
                              doc['workerStatus'] ??
                              doc['employmentStatus'] ??
                              'Inactive')
                          .toString()
                          .toUpperCase()
                    : (isLimitReached ? 'limit_reached'.tr() : 'assign'.tr());
                final Color actionColor = !canAssign || isLimitReached
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF0D4CC6);

                return GestureDetector(
                  onTap: () {
                    final isGuest =
                        _authService.currentUser?.isAnonymous ?? false;
                    if (isGuest) {
                      showGuestRestrictionDialog(context);
                      return;
                    }
                    if (isLimitReached || doc['canAssignTimeOff'] == false) {
                      _showTimeOffDataDialog(context, doc, index);
                      return;
                    }
                    if (widget.onAssignTimeOff != null) {
                      widget.onAssignTimeOff!(_docForNewLeave(doc));
                    } else {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (context) => AssignTimeOffScreen(
                                onBack: () => Navigator.of(context).pop(),
                                initialWorker: _docForNewLeave(doc),
                              ),
                            ),
                          )
                          .then((_) {
                            if (!isGuest) return;
                            _refreshGuestData();
                          });
                    }
                  },
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
                              LocalizationHelper.localizePosition(position),
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
                                final isGuest =
                                    _authService.currentUser?.isAnonymous ??
                                    false;
                                if (isGuest) {
                                  showGuestRestrictionDialog(context);
                                  return;
                                }

                                if (isLimitReached ||
                                    doc['canAssignTimeOff'] == false) {
                                  _showTimeOffDataDialog(context, doc, index);
                                  return;
                                }
                                if (widget.onAssignTimeOff != null) {
                                  widget.onAssignTimeOff!(_docForNewLeave(doc));
                                } else {
                                  Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              AssignTimeOffScreen(
                                                onBack: () =>
                                                    Navigator.of(context).pop(),
                                                initialWorker: _docForNewLeave(
                                                  doc,
                                                ),
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
                                        displayAction,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: actionColor,
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
    final String notes = (data['notes'] ?? '').toString();

    final String workerId = (data['workerId'] ?? data['id'] ?? '')
        .toString()
        .trim();
    final normalizedEmail = email.trim().toLowerCase();
    final workerRecords = _rawTimeoffDocs.where((d) {
      if (!TimeOffService.isActiveRecord(d)) return false;
      final recWorkerId = (d['workerId'] ?? '').toString().trim();
      final recEmail = (d['email'] ?? '').toString().trim().toLowerCase();
      if (workerId.isNotEmpty && workerId == recWorkerId) return true;
      if (normalizedEmail.isNotEmpty && normalizedEmail == recEmail) {
        return true;
      }
      return false;
    }).toList();

    final leaveDatesByType = TimeOffService.leaveDatesByTypeForWorker(
      data,
      workerRecords,
    );
    final totalLeaveDays = leaveDatesByType.values.fold<int>(
      0,
      (total, dates) => total + dates.length,
    );
    final String selectedDays = totalLeaveDays.toString();

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth * 0.92 : 460.0;

    final List<Map<String, dynamic>> allDatesWithTypes = [];
    for (final entry in leaveDatesByType.entries) {
      for (final date in entry.value) {
        allDatesWithTypes.add({'date': date, 'type': entry.key});
      }
    }
    allDatesWithTypes.sort(
      (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
    );

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
            height: 420,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final cardWidth = (constraints.maxWidth - 12) / 2;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildTimeOffMetricCard(
                                      icon: const Icon(
                                        Icons.event_available,
                                        color: Color(0xFF004FDE),
                                        size: 20,
                                      ),
                                      title: 'total_leave_days'.tr(),
                                      value: selectedDays,
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildTimeOffMetricCard(
                                      icon: const Icon(
                                        Icons.calendar_month,
                                        color: Color(0xFF004FDE),
                                        size: 20,
                                      ),
                                      title: 'requested_days'.tr(),
                                      value: selectedDays,
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildTimeOffMetricCard(
                                      icon: const Icon(
                                        Icons.beach_access,
                                        color: Color(0xFF004FDE),
                                        size: 20,
                                      ),
                                      title: 'remaining_days'.tr(),
                                      value:
                                          '${TimeOffService.totalAvailableLeaves(data)}',
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildTimeOffMetricCard(
                                      icon: const Icon(
                                        Icons.date_range,
                                        color: Color(0xFF004FDE),
                                        size: 20,
                                      ),
                                      title: 'selected_dates'.tr(),
                                      value: _formatSelectedDatesSummary(
                                        allDatesWithTypes,
                                      ),
                                      onTap: () {
                                        _showSelectedDatesDialog(
                                          context,
                                          allDatesWithTypes,
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
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
                                ],
                              );
                            },
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
      final wId = (data['workerId'] ?? data['id'] ?? '').toString().trim();
      final wEmail = (data['email'] ?? '').toString().trim().toLowerCase();

      final activeRecords = _rawTimeoffDocs.where((r) {
        if (!TimeOffService.isActiveRecord(r)) return false;
        final rId = (r['workerId'] ?? '').toString().trim();
        final rEmail = (r['email'] ?? '').toString().trim().toLowerCase();
        return (wId.isNotEmpty && wId == rId) ||
            (wEmail.isNotEmpty && wEmail == rEmail);
      }).toList();

      Map<String, dynamic>? latestRecord;
      if (activeRecords.isNotEmpty) {
        latestRecord = activeRecords.reduce((a, b) {
          final aId = (a['id'] ?? '').toString();
          final bId = (b['id'] ?? '').toString();
          return aId.compareTo(bId) >= 0 ? a : b;
        });
      }

      if (latestRecord == null ||
          !TimeOffService.isEditableRecord(latestRecord)) {
        FlashySnackBar.show(
          this.context,
          message: 'past_time_off_edit_blocked'.tr(),
          isError: true,
        );
        return;
      }

      final mergedWorker = <String, dynamic>{...data};
      mergedWorker.addAll(latestRecord);
      mergedWorker['_aggregateTimeOffEdit'] = true;
      mergedWorker['_aggregateDatesByType'] = leaveDatesByType;

      setState(() {
        _isAssigningTimeOff = true;
        _workerForTimeOff = mergedWorker;
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
    VoidCallback? onTap,
  }) {
    final cardWidget = Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
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

    if (onTap == null) return cardWidget;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: cardWidget),
    );
  }

  String _formatSelectedDatesSummary(
    List<Map<String, dynamic>> datesWithTypes,
  ) {
    if (datesWithTypes.isEmpty) return 'select_date'.tr();
    String formatDate(DateTime date) {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day/$month/${date.year}';
    }

    final visibleDates = datesWithTypes
        .take(3)
        .map((e) => formatDate(e['date'] as DateTime))
        .join(', ');
    final remaining = datesWithTypes.length - 3;
    return remaining > 0 ? '$visibleDates +$remaining' : visibleDates;
  }

  void _showSelectedDatesDialog(
    BuildContext context,
    List<Map<String, dynamic>> datesWithTypes, [
    String? leaveType,
  ]) {
    const typeOrder = [
      'Annual Leave',
      'Sick Leave',
      'Casual Leave',
      'Medical Leave',
    ];
    final assignedDatesByType = <String, Set<DateTime>>{
      for (final type in typeOrder) type: <DateTime>{},
    };
    for (final item in datesWithTypes) {
      final type = TimeOffService.normalizeLeaveType(
        (item['type'] ?? '').toString(),
      );
      final date = item['date'];
      if (date is DateTime && assignedDatesByType.containsKey(type)) {
        assignedDatesByType[type]!.add(
          DateTime(date.year, date.month, date.day),
        );
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 520,
          height: MediaQuery.sizeOf(ctx).height * 0.60,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(ctx).width * 0.90,
            minHeight: 340,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
          ),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: const BoxDecoration(color: Color(0xFF004FDE)),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'selected_dates_count_title'.tr(
                          namedArgs: {'count': '${datesWithTypes.length}'},
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                color: const Color(0xFFF8FAFC),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: typeOrder.map((type) {
                    final color = LeaveColors.getColor(type);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LeaveColors.getBgColor(type),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '${_localizedLeaveType(type)}: '
                        '${assignedDatesByType[type]!.length} ${assignedDatesByType[type]!.length == 1 ? 'day'.tr() : 'days'.tr()}',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: datesWithTypes.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 40,
                              horizontal: 24,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.event_busy_rounded,
                                    size: 32,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'no_dates_selected'.tr(),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          itemCount: datesWithTypes.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: Color(0xFFEEEEEE),
                          ),
                          itemBuilder: (context, index) {
                            final item = datesWithTypes[index];
                            final date = item['date'] as DateTime;
                            final type = item['type'] as String?;
                            final effectiveType = (type?.isNotEmpty == true)
                                ? type
                                : leaveType;
                            final String displayType = effectiveType == null
                                ? ''
                                : _localizedLeaveType(effectiveType);
                            final localeName = context.locale.toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE5EEFC),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Color(0xFF004FDE),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat.yMMMd(
                                            localeName,
                                          ).format(date),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        Text(
                                          DateFormat.EEEE(
                                            localeName,
                                          ).format(date),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF666666),
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (displayType.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: LeaveColors.getBgColor(
                                          effectiveType ?? '',
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        displayType,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: LeaveColors.getColor(
                                            effectiveType ?? '',
                                          ),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final double dynamicHeight = (MediaQuery.of(context).size.height - 329)
        .clamp(440.0, 1200.0);
    final bool hasActiveFilters = _isDropdownFilterActive;
    final String filterName = _activeFilterName;
    final String emptyMessage = hasActiveFilters
        ? (filterName.isNotEmpty
              ? _l(
                  'no_records_named_filter',
                  'No time off records found for "$filterName".',
                )
              : _l(
                  'no_records_selected_filter',
                  'No time off records found for the selected filter.',
                ))
        : 'no_time_off_records'.tr();

    return Container(
      width: double.infinity,
      height: dynamicHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/placeholder_workers.svg',
            width: 120,
            height: 100,
            colorFilter: const ColorFilter.mode(
              Color(0xFFCBCBCB),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsFiltersAndExportRow() {
    final periodOptions = [
      {'value': 'All Time', 'label': _l('all_time', 'All Time')},
      {'value': 'This Month', 'label': _l('this_month', 'This Month')},
      {'value': 'Last 6 Months', 'label': _l('last_6_months', 'Last 6 Months')},
      {'value': 'This Year', 'label': _l('this_year', 'This Year')},
      {'value': 'Custom Range', 'label': _l('custom_range', 'Custom Range')},
    ];

    final leaveTypeOptions = [
      {'value': 'All', 'label': _l('all_filter', 'All')},
      {'value': 'Sick Leave', 'label': _localizedLeaveType('Sick Leave')},
      {'value': 'Casual Leave', 'label': _localizedLeaveType('Casual Leave')},
      {'value': 'Medical Leave', 'label': _localizedLeaveType('Medical Leave')},
      {'value': 'Annual Leave', 'label': _localizedLeaveType('Annual Leave')},
    ];

    final match = periodOptions.firstWhere(
      (e) => e['value'] == _recordsPeriodFilter,
      orElse: () => {
        'value': _recordsPeriodFilter,
        'label': _recordsPeriodFilter,
      },
    );
    String periodLabel = match['label']!;
    if (_recordsPeriodFilter == 'Custom Range' && _customDateRange != null) {
      final start = _customDateRange!.start;
      final end = _customDateRange!.end;
      if (start.year == end.year &&
          start.month == end.month &&
          start.day == end.day) {
        periodLabel = DateFormat('dd MMM').format(start);
      } else if (start.year == end.year) {
        periodLabel =
            '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM').format(end)}';
      } else {
        periodLabel =
            '${DateFormat('dd MMM yy').format(start)} - ${DateFormat('dd MMM yy').format(end)}';
      }
    }

    String leaveTypeLabel = _recordsLeaveTypeFilter == 'All'
        ? _l('all_filter', 'All')
        : _localizedLeaveType(_recordsLeaveTypeFilter);

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          tooltip: '',
          constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
          onSelected: (val) {
            if (val == 'Custom Range') {
              _selectCustomDateRange(context);
            } else {
              setState(() {
                _recordsPeriodFilter = val;
                _customDateRange = null;
              });
            }
          },
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          color: const Color(0xFFFFFFFF),
          elevation: 4,
          itemBuilder: (context) {
            return periodOptions.map((f) {
              final bool selected = _recordsPeriodFilter == f['value'];
              final label = f['label']!;
              return PopupMenuItem<String>(
                value: f['value']!,
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF0247C4)
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                        color: selected
                            ? const Color(0xFF0247C4)
                            : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              size: 10,
                              color: Color(0xFFFFFFFF),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected
                              ? const Color(0xFF0247C4)
                              : const Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0247C4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  periodLabel,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '',
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 150),
          onSelected: (val) {
            setState(() {
              _recordsLeaveTypeFilter = val;
            });
          },
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          color: const Color(0xFFFFFFFF),
          elevation: 4,
          itemBuilder: (context) {
            return leaveTypeOptions.map((f) {
              final bool selected = _recordsLeaveTypeFilter == f['value'];
              return PopupMenuItem<String>(
                value: f['value']!,
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF0247C4)
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                        color: selected
                            ? const Color(0xFF0247C4)
                            : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              size: 10,
                              color: Color(0xFFFFFFFF),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f['label']!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected
                              ? const Color(0xFF0247C4)
                              : const Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0247C4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/filter.png',
                  width: 18,
                  height: 18,
                  color: const Color(0xFFFFFFFF),
                ),
                const SizedBox(width: 6),
                Text(
                  leaveTypeLabel,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: _isExportingCsv ? null : _handleExportCsv,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF27AE60),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isExportingCsv)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.file_download_outlined,
                    size: 20,
                    color: Colors.white,
                  ),
                const SizedBox(width: 6),
                Text(
                  _l('export_csv', 'Export CSV'),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DateTime? _dateAtPosition(Offset position, DateTime monthDate) {
    const double cellWidth = 48.0;
    const double cellHeight = 40.0;
    const double headerHeight = 30.0;

    final column = (position.dx / cellWidth).floor();
    final row = ((position.dy - headerHeight) / cellHeight).floor();

    if (column < 0 || column > 6 || row < 0) return null;

    final firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1);
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final startOffset = firstDayOfMonth.weekday % 7;

    final day = (row * 7) + column - startOffset + 1;
    if (day < 1 || day > daysInMonth) return null;
    return DateTime(monthDate.year, monthDate.month, day);
  }

  Widget _buildCalendarGrid(
    DateTime calendarDate,
    Set<DateTime> selectedDates,
  ) {
    final weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    final firstDayOfMonth = DateTime(calendarDate.year, calendarDate.month, 1);
    final daysInMonth = DateTime(
      calendarDate.year,
      calendarDate.month + 1,
      0,
    ).day;
    final startOffset = firstDayOfMonth.weekday % 7;
    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekdays.map((day) {
            return SizedBox(
              width: 44,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 40,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            final dayNumber = index - startOffset + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox();
            }
            final cellDate = DateTime(
              calendarDate.year,
              calendarDate.month,
              dayNumber,
            );
            final isSelected = selectedDates.any(
              (d) =>
                  d.year == cellDate.year &&
                  d.month == cellDate.month &&
                  d.day == cellDate.day,
            );

            return Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF0247C4)
                    : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF0247C4)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Center(
                child: Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _selectCustomDateRange(BuildContext context) async {
    DateTime calendarDate = DateTime.now();
    Set<DateTime> selectedDates = {};
    if (_recordsPeriodFilter == 'Custom Range' && _customDateRange != null) {
      for (
        var d = _customDateRange!.start;
        !d.isAfter(_customDateRange!.end);
        d = d.add(const Duration(days: 1))
      ) {
        selectedDates.add(DateTime(d.year, d.month, d.day));
      }
      calendarDate = _customDateRange!.start;
    }

    DateTime? dragAnchorDate;
    Offset? dragStartPosition;
    bool dragMoved = false;
    Set<DateTime> selectionBeforeDrag = {};

    final result = await showDialog<List<DateTime>?>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: const Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 380,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 0,
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.black,
                                size: 20,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          Center(
                            child: Text(
                              'select_dates'.tr(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF000000),
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 22),
                          onPressed: () {
                            setModalState(() {
                              calendarDate = DateTime(
                                calendarDate.year,
                                calendarDate.month - 1,
                              );
                            });
                          },
                        ),
                        Text(
                          DateFormat(
                            'MMMM yyyy',
                          ).format(calendarDate).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 22),
                          onPressed: () {
                            setModalState(() {
                              calendarDate = DateTime(
                                calendarDate.year,
                                calendarDate.month + 1,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Listener(
                      onPointerDown: (event) {
                        final date = _dateAtPosition(
                          event.localPosition,
                          calendarDate,
                        );
                        dragAnchorDate = date;
                        dragStartPosition = event.localPosition;
                        dragMoved = false;
                        selectionBeforeDrag = Set<DateTime>.from(selectedDates);
                        setModalState(() {});
                      },
                      onPointerMove: (event) {
                        final startPos = dragStartPosition;
                        if (startPos != null && !dragMoved) {
                          final dx = (event.localPosition.dx - startPos.dx)
                              .abs();
                          final dy = (event.localPosition.dy - startPos.dy)
                              .abs();
                          if (dx > 5 || dy > 5) {
                            dragMoved = true;
                          }
                        }
                        if (!dragMoved) return;
                        final anchor = dragAnchorDate;
                        if (anchor == null) return;
                        final current = _dateAtPosition(
                          event.localPosition,
                          calendarDate,
                        );
                        if (current == null) return;
                        setModalState(() {
                          selectedDates.clear();
                          selectedDates.addAll(selectionBeforeDrag);
                          final isDragRemoving = selectionBeforeDrag.contains(
                            anchor,
                          );
                          final start = anchor.isBefore(current)
                              ? anchor
                              : current;
                          final end = anchor.isAfter(current)
                              ? anchor
                              : current;
                          for (
                            var d = start;
                            !d.isAfter(end);
                            d = d.add(const Duration(days: 1))
                          ) {
                            if (isDragRemoving) {
                              selectedDates.remove(d);
                            } else {
                              selectedDates.add(d);
                            }
                          }
                        });
                      },
                      onPointerUp: (event) {
                        if (!dragMoved && dragAnchorDate != null) {
                          final date = dragAnchorDate!;
                          setModalState(() {
                            final isAlreadySelected = selectedDates.any(
                              (d) =>
                                  d.year == date.year &&
                                  d.month == date.month &&
                                  d.day == date.day,
                            );
                            if (isAlreadySelected) {
                              selectedDates.removeWhere(
                                (d) =>
                                    d.year == date.year &&
                                    d.month == date.month &&
                                    d.day == date.day,
                              );
                            } else {
                              selectedDates.add(date);
                            }
                          });
                        }
                        dragAnchorDate = null;
                        dragStartPosition = null;
                        dragMoved = false;
                        selectionBeforeDrag = {};
                        setModalState(() {});
                      },
                      child: _buildCalendarGrid(calendarDate, selectedDates),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedDates.isEmpty
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF0247C4),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          elevation: 0,
                        ),
                        onPressed: selectedDates.isEmpty
                            ? null
                            : () {
                                final sortedDates = selectedDates.toList()
                                  ..sort();
                                Navigator.of(context).pop(sortedDates);
                              },
                        child: Text(
                          _l('apply', 'Apply'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _customDateRange = DateTimeRange(start: result.first, end: result.last);
        _recordsPeriodFilter = 'Custom Range';
      });
    }
  }

  Future<void> _handleExportCsv() async {
    if (_isExportingCsv) return;
    final records = _filteredTimeOffRecords;
    if (records.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'no_time_off_records'.tr(),
        isError: true,
      );
      return;
    }
    setState(() => _isExportingCsv = true);
    try {
      await _exportTimeOffCsv(records);
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  Future<void> _exportTimeOffCsv(List<Map<String, dynamic>> records) async {
    final periodLabel =
        _recordsPeriodFilter == 'Custom Range' && _customDateRange != null
        ? '${DateFormat('dd MMM yyyy').format(_customDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_customDateRange!.end)}'
        : _recordsPeriodFilter;

    final fileName =
        'time_off_${periodLabel.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.csv';
    final success = await TimeOffExportService.exportCsv(
      records: records,
      fileName: fileName,
    );
    if (success && mounted) {
      FlashySnackBar.show(
        context,
        message: 'file_saved_and_opened'.tr(namedArgs: {'file': fileName}),
      );
    }
  }
}
