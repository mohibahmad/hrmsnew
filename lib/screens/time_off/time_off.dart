import 'package:hrms/core/utils/utils.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/services/attendance/attendance_report_service.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/time_off/time_off_export_service.dart';
import 'package:hrms/services/time_off/time_off_service.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/common/notification_bell.dart';
import 'package:hrms/widgets/common/screen_table_shimmer.dart';
import 'package:hrms/screens/time_off/assign_time_off.dart';

const _kBlue = Color(0xFF0247C4);
const _kDarkBlue = Color(0xFF004FDE);
const _kActionBlue = Color(0xFF0D4CC6);
const _kWhite = Color(0xFFFFFFFF);
const _kBlack = Color(0xFF000000);
const _kBg = Color(0xFFF8FAFC);
const _kRowBg = Color(0xFFF6F8FA);
const _kBorder = Color(0xFFEEEEEE);
const _kDivider = Color(0xFFF7F8FC);
const _kCardBorder = Color(0xFFE8E8E8);
const _kGrey666 = Color(0xFF666666);
const _kGreen = Color(0xFF27AE60);
const _kRed = Color(0xFFDC2626);
const _kLightBlue = Color(0xFFE5EEFC);
const _kGrey333 = Color(0xFF333333);
const _kPlaceholder = Color(0xFFCBCBCB);

const _kFontFamily = 'SF Pro Display';

const _kHeaderStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 16,
  color: _kBlack,
  fontFamily: _kFontFamily,
);

const _kWhiteText16w500 = TextStyle(
  color: _kWhite,
  fontSize: 16,
  fontWeight: FontWeight.w500,
  fontFamily: _kFontFamily,
);

const _kInactiveStatuses = {'inactive', 'terminated', 'deleted', 'archived'};

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
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedTab = 'All';
  String _recordsPeriodFilter = 'All Time';
  String _recordsLeaveTypeFilter = 'All';
  DateTimeRange? _customDateRange;
  Set<DateTime>? _customSelectedDates;

  List<Map<String, dynamic>> _rawTimeoffDocs = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _timeoffDocs = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _workersList = <Map<String, dynamic>>[];

  bool _isLoading = true;
  bool _isExportingCsv = false;
  bool _workersLoaded = false;
  bool _timeoffLoaded = false;
  bool _workersLoadFailed = false;
  bool _timeoffLoadFailed = false;
  bool _isAssigningTimeOff = false;

  Map<String, dynamic>? _workerForTimeOff;

  late final AuthService _authService;
  late final bool _isGuestMode;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _isGuestMode = _authService.currentUser?.isAnonymous ?? false;

    if (_isGuestMode) {
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
      _workersLoaded = true;
      _timeoffLoaded = true;
      _combineTimeOff();
    } else {
      _initStreams();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initStreams() {
    ref.listenAsync(
      workersProvider,
      (records) {
        if (!mounted) return;
        setState(() {
          _workersList = records;
          _workersLoaded = true;
          _workersLoadFailed = false;
          _combineTimeOff();
        });
      },
      onError: (Object error, StackTrace st) {
        ErrorReporter.report(error, st, context: 'timeOffWorkersStream');
        if (!mounted) return;
        setState(() {
          _workersList = <Map<String, dynamic>>[];
          _workersLoaded = true;
          _workersLoadFailed = true;
          _combineTimeOff();
        });
      },
    );

    ref.listenAsync(
      timeOffProvider,
      (records) {
        if (!mounted) return;
        setState(() {
          final docs = sortedFirestoreRecords(records);

          _rawTimeoffDocs = docs;
          _timeoffLoaded = true;
          _timeoffLoadFailed = false;
          _combineTimeOff();
        });
      },
      onError: (Object error, StackTrace st) {
        ErrorReporter.report(error, st, context: 'timeOffRecordsStream');
        if (!mounted) return;
        setState(() {
          _rawTimeoffDocs = <Map<String, dynamic>>[];
          _timeoffLoaded = true;
          _timeoffLoadFailed = true;
          _combineTimeOff();
        });
      },
    );
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

  bool _isAttendanceManaged(Map<String, dynamic> record) =>
      _normalizedValue(record['source']) == 'attendance';

  String _firstNonEmpty(Iterable<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return '';
  }

  bool _hasUniqueWorkerName(String name) {
    if (name.isEmpty) return false;
    var count = 0;
    for (final w in _workersList) {
      if (_normalizedValue(w['name']) == name && ++count > 1) return false;
    }
    return count == 1;
  }

  int _remainingPaidLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> records,
  ) {
    final total = TimeOffService.configuredPaidLeaveAllowance(worker);
    final used = TimeOffService.paidDaysUsedForWorker(worker, records);
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
    final status = _normalizedValue(
      worker['employmentStatus'] ??
          worker['workerStatus'] ??
          worker['status'] ??
          'Active',
    );
    return !_kInactiveStatuses.contains(status);
  }

  int _compareRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aHas = (a['action'] ?? '').toString().isNotEmpty;
    final bHas = (b['action'] ?? '').toString().isNotEmpty;
    if (aHas != bHas) return aHas ? -1 : 1;

    final aStart = TimeOffService.parseDate(a['startDate']);
    final bStart = TimeOffService.parseDate(b['startDate']);
    if (aStart != null && bStart != null) {
      final cmp = bStart.compareTo(aStart);
      if (cmp != 0) return cmp;
    } else if (aStart != null) {
      return -1;
    } else if (bStart != null) {
      return 1;
    }

    final byName = _normalizedValue(
      a['name'],
    ).compareTo(_normalizedValue(b['name']));
    if (byName != 0) return byName;

    return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
  }

  bool _matchesFilter(String position, String filter) =>
      filter == 'All' || position.toLowerCase().contains(filter.toLowerCase());

  bool get _isDropdownFilterActive =>
      _recordsPeriodFilter != 'All Time' || _recordsLeaveTypeFilter != 'All';

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
        final normType = TimeOffService.leaveType(record);
        final normSelected = TimeOffService.normalizeLeaveType(
          _recordsLeaveTypeFilter,
        );
        if (normType != normSelected) return false;
      }

      final recordDates = TimeOffService.selectedDatesForRecord(record);

      if (_recordsPeriodFilter == 'Custom Range') {
        if (!_matchesCustomRange(record, recordDates)) return false;
      } else if (_recordsPeriodFilter != 'All Time') {
        if (!_matchesPeriodRange(record, recordDates)) return false;
      }

      return true;
    }).toList();
  }

  bool _matchesCustomRange(
    Map<String, dynamic> record,
    List<DateTime> recordDates,
  ) {
    if (_customSelectedDates != null && _customSelectedDates!.isNotEmpty) {
      return _matchesSelectedDates(record, recordDates, _customSelectedDates!);
    }
    if (_customDateRange != null) {
      return _matchesDateRange(record, recordDates, _customDateRange!);
    }
    return true;
  }

  bool _matchesSelectedDates(
    Map<String, dynamic> record,
    List<DateTime> recordDates,
    Set<DateTime> selected,
  ) {
    bool datesMatch(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return selected.any(
        (s) => s.year == day.year && s.month == day.month && s.day == day.day,
      );
    }

    if (recordDates.isEmpty) {
      final fallback = AppDateUtils.dateFromValue(
        record['startDate'] ?? record['date'],
      );
      if (fallback == null) return true;
      return datesMatch(fallback);
    }

    return recordDates.any(datesMatch);
  }

  bool _matchesDateRange(
    Map<String, dynamic> record,
    List<DateTime> recordDates,
    DateTimeRange range,
  ) {
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
    );

    bool inRange(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }

    if (recordDates.isEmpty) {
      final fallback = AppDateUtils.dateFromValue(
        record['startDate'] ?? record['date'],
      );
      if (fallback == null) return true;
      return inRange(fallback);
    }

    return recordDates.any(inRange);
  }

  bool _matchesPeriodRange(
    Map<String, dynamic> record,
    List<DateTime> recordDates,
  ) {
    final range = AttendanceReportService.rangeForPeriod(_recordsPeriodFilter);

    if (recordDates.isEmpty) {
      final fallback = AppDateUtils.dateFromValue(
        record['startDate'] ?? record['date'],
      );
      if (fallback == null) return true;
      return range.contains(
        DateTime(fallback.year, fallback.month, fallback.day),
      );
    }

    return recordDates.any(
      (d) => range.contains(DateTime(d.year, d.month, d.day)),
    );
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final query = _searchQuery.toLowerCase();

    final filtered = _timeoffDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final position = (doc['position'] ?? '').toString().toLowerCase();

      if (!name.contains(query) && !position.contains(query)) return false;
      return _matchesFilter(position, _selectedTab);
    }).toList();

    filtered.sort(
      _isGuestMode
          ? (a, b) {
              final aAction = (a['action'] ?? '').toString();
              final bAction = (b['action'] ?? '').toString();
              if (aAction.isNotEmpty && bAction.isEmpty) return -1;
              if (aAction.isEmpty && bAction.isNotEmpty) return 1;
              return 0;
            }
          : _compareRows,
    );

    return filtered;
  }

  List<Map<String, dynamic>> get _matchingWorkersForDropdownFilters {
    final filteredWorkers = _filteredWorkers;
    final filteredRecords = _filteredTimeOffRecords;

    final recordIds = <String>{};
    final recordEmails = <String>{};

    for (final rec in filteredRecords) {
      final rId = (rec['workerId'] ?? rec['id'] ?? '').toString().trim();
      final rEmail = (rec['workerEmail'] ?? rec['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (rId.isNotEmpty) recordIds.add(rId);
      if (rEmail.isNotEmpty) recordEmails.add(rEmail);
    }

    return filteredWorkers.where((worker) {
      final wId = (worker['id'] ?? worker['workerId'] ?? '').toString().trim();
      final wEmail = (worker['email'] ?? worker['workerEmail'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      return (wId.isNotEmpty && recordIds.contains(wId)) ||
          (wEmail.isNotEmpty && recordEmails.contains(wEmail));
    }).toList();
  }

  List<Map<String, dynamic>> get _displayWorkers => _isDropdownFilterActive
      ? _matchingWorkersForDropdownFilters
      : _filteredWorkers;

  String get _activeFilterName {
    final parts = <String>[];

    if (_recordsLeaveTypeFilter != 'All') {
      parts.add(_localizedLeaveType(_recordsLeaveTypeFilter));
    }

    if (_recordsPeriodFilter != 'All Time') {
      if (_recordsPeriodFilter == 'Custom Range' && _customDateRange != null) {
        final s = _customDateRange!.start;
        final e = _customDateRange!.end;
        parts.add(
          s.year == e.year && s.month == e.month && s.day == e.day
              ? DateFormat('dd MMM').format(s)
              : '${DateFormat('dd MMM').format(s)} - ${DateFormat('dd MMM').format(e)}',
        );
      } else {
        parts.add(
          _periodOptions.firstWhere(
            (o) => o['value'] == _recordsPeriodFilter,
            orElse: () => {
              'value': _recordsPeriodFilter,
              'label': _recordsPeriodFilter,
            },
          )['label']!,
        );
      }
    }

    return parts.join(' • ');
  }

  List<Map<String, String>> get _periodOptions => [
    {'value': 'All Time', 'label': 'all_time'.tr()},
    {'value': 'This Month', 'label': 'this_month'.tr()},
    {'value': 'Last 6 Months', 'label': 'last_6_months'.tr()},
    {'value': 'This Year', 'label': 'this_year'.tr()},
    {'value': 'Custom Range', 'label': 'custom_range'.tr()},
  ];

  List<Map<String, String>> get _leaveTypeOptions => [
    {'value': 'All', 'label': 'all_filter'.tr()},
    {'value': 'Sick Leave', 'label': _localizedLeaveType('Sick Leave')},
    {'value': 'Casual Leave', 'label': _localizedLeaveType('Casual Leave')},
    {'value': 'Medical Leave', 'label': _localizedLeaveType('Medical Leave')},
    {'value': 'Annual Leave', 'label': _localizedLeaveType('Annual Leave')},
  ];

  void _combineTimeOff() {
    if (_isGuestMode) {
      _combineGuestTimeOff();
      return;
    }

    if (!_workersLoaded || !_timeoffLoaded) {
      _isLoading = true;
      return;
    }

    if (_workersLoadFailed || _timeoffLoadFailed || _workersList.isEmpty) {
      _timeoffDocs = <Map<String, dynamic>>[];
      _isLoading = false;
      return;
    }

    final recordsByWorkerId = <String, List<Map<String, dynamic>>>{};
    final legacyByEmail = <String, List<Map<String, dynamic>>>{};
    final allByWorkerId = <String, List<Map<String, dynamic>>>{};
    final allLegacyByEmail = <String, List<Map<String, dynamic>>>{};

    for (final record in _rawTimeoffDocs) {
      if (!TimeOffService.isActiveRecord(record)) continue;

      final wId = (record['workerId'] ?? '').toString().trim();
      final email = _normalizedValue(record['email']);
      final isAtt = _isAttendanceManaged(record);

      if (wId.isNotEmpty) {
        allByWorkerId
            .putIfAbsent(wId, () => <Map<String, dynamic>>[])
            .add(record);
        if (!isAtt) {
          recordsByWorkerId
              .putIfAbsent(wId, () => <Map<String, dynamic>>[])
              .add(record);
        }
      } else if (email.isNotEmpty) {
        allLegacyByEmail
            .putIfAbsent(email, () => <Map<String, dynamic>>[])
            .add(record);
        if (!isAtt) {
          legacyByEmail
              .putIfAbsent(email, () => <Map<String, dynamic>>[])
              .add(record);
        }
      }
    }

    final combined = <Map<String, dynamic>>[];

    for (final worker in _workersList) {
      final wId = (worker['id'] ?? '').toString().trim();
      final email = _normalizedValue(worker['email']);
      final name = _normalizedValue(worker['name']);
      final canUseName = email.isEmpty && _hasUniqueWorkerName(name);

      List<Map<String, dynamic>> matching;
      List<Map<String, dynamic>> balance;

      if (wId.isNotEmpty) {
        matching = recordsByWorkerId[wId] ?? const [];
        balance = allByWorkerId[wId] ?? const [];
      } else if (email.isNotEmpty) {
        matching = legacyByEmail[email] ?? const [];
        balance = allLegacyByEmail[email] ?? const [];
      } else {
        balance = _rawTimeoffDocs.where((r) {
          if (!TimeOffService.isActiveRecord(r)) return false;
          if ((r['workerId'] ?? '').toString().trim().isNotEmpty) return false;
          if (_normalizedValue(r['email']).isNotEmpty) return false;
          final rName = _normalizedValue(r['name'] ?? r['workerName']);
          return canUseName && name.isNotEmpty && rName == name;
        }).toList();

        matching = balance.where((r) => !_isAttendanceManaged(r)).toList();
      }

      final remaining = _remainingPaidLeave(worker, balance);

      if (matching.isEmpty) {
        combined.add({
          ...worker,
          'workerId': wId,
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

      final sorted = List<Map<String, dynamic>>.from(matching)
        ..sort((a, b) {
          final aS = TimeOffService.parseDate(a['startDate']);
          final bS = TimeOffService.parseDate(b['startDate']);
          if (aS == null && bS == null) return 0;
          if (aS == null) return 1;
          if (bS == null) return -1;
          return bS.compareTo(aS);
        });

      final rec = sorted.first;
      final phone = _firstNonEmpty([
        worker['phone'],
        worker['contact'],
        rec['phone'],
        rec['contact'],
      ]);

      combined.add({
        ...worker,
        ...rec,
        'workerId': wId.isNotEmpty ? wId : (rec['workerId'] ?? '').toString(),
        'action': TimeOffService.leaveType(rec),
        'type': TimeOffService.leaveType(rec),
        'name': _firstNonEmpty([
          worker['name'],
          rec['name'],
          rec['workerName'],
        ]),
        'email': _firstNonEmpty([worker['email'], rec['email']]),
        'profileImage': _firstNonEmpty([
          worker['profileImage'],
          rec['profileImage'],
          rec['workerAvatar'],
        ]),
        'phone': phone,
        'contact': phone,
        'annualLeaves': worker['annualLeaves'],
        'availableAnnualLeaves': worker['availableAnnualLeaves'],
        'remainingLeaves': remaining.toString(),
        'canAssignTimeOff': _canAssignTimeOff(worker),
      });
    }

    combined.sort(_compareRows);
    _timeoffDocs = combined;
    _isLoading = false;
  }

  void _combineGuestTimeOff() {
    if (_workersList.isEmpty) {
      _timeoffDocs = <Map<String, dynamic>>[];
      _isLoading = false;
      return;
    }

    final combined = <Map<String, dynamic>>[];

    for (final worker in _workersList) {
      final allowNameMatch = (worker['email'] ?? '').toString().trim().isEmpty;

      bool workerMatches(Map<String, dynamic> r) =>
          WorkerIdentity.recordsMatch(r, worker, allowName: allowNameMatch);

      final matching = _rawTimeoffDocs
          .where(
            (r) =>
                TimeOffService.isActiveRecord(r) &&
                !_isAttendanceManaged(r) &&
                workerMatches(r),
          )
          .toList();

      final balanceRecords = _rawTimeoffDocs
          .where((r) => TimeOffService.isActiveRecord(r) && workerMatches(r))
          .toList();

      final remaining = TimeOffService.remainingPaidLeave(
        worker,
        balanceRecords,
      );

      final phone = _firstNonEmpty([
        worker['contact'],
        worker['phone'],
        worker['contactNo'],
        worker['phoneNumber'],
        worker['phoneNo'],
        worker['mobile'],
      ]);

      if (matching.isEmpty) {
        combined.add({
          ...worker,
          'phone': phone,
          'contact': phone,
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

      final sorted = List<Map<String, dynamic>>.from(matching)
        ..sort((a, b) {
          final aS = TimeOffService.parseDate(a['startDate']);
          final bS = TimeOffService.parseDate(b['startDate']);
          if (aS == null && bS == null) return 0;
          if (aS == null) return 1;
          if (bS == null) return -1;
          return bS.compareTo(aS);
        });

      final rec = sorted.first;
      final recPhone = _firstNonEmpty([
        worker['contact'],
        worker['phone'],
        worker['contactNo'],
        worker['phoneNumber'],
        worker['phoneNo'],
        worker['mobile'],
        rec['contact'],
        rec['phone'],
      ]);

      combined.add({
        ...worker,
        ...rec,
        'workerId': (worker['id'] ?? worker['workerId'] ?? rec['workerId'] ?? '').toString(),
        'action': TimeOffService.leaveType(rec),
        'type': TimeOffService.leaveType(rec),
        'name': _firstNonEmpty([
          worker['name'],
          rec['name'],
          rec['workerName'],
        ]),
        'email': _firstNonEmpty([worker['email'], rec['email']]),
        'profileImage': _firstNonEmpty([
          worker['profileImage'],
          rec['profileImage'],
          rec['workerAvatar'],
        ]),
        'phone': recPhone,
        'contact': recPhone,
        'annualLeaves': worker['annualLeaves'],
        'availableAnnualLeaves': worker['availableAnnualLeaves'],
        'remainingLeaves': remaining.toString(),
        'canAssignTimeOff': _canAssignTimeOff(worker),
      });
    }

    combined.sort((a, b) {
      final aHas = (a['action'] ?? '').toString().isNotEmpty;
      final bHas = (b['action'] ?? '').toString().isNotEmpty;
      if (aHas != bHas) return aHas ? -1 : 1;

      final aS = TimeOffService.parseDate(a['startDate']);
      final bS = TimeOffService.parseDate(b['startDate']);
      if (aS == null || bS == null) return 0;
      return bS.compareTo(aS);
    });

    _timeoffDocs = combined;
    _isLoading = false;
  }

  void _refreshGuestData() {
    if (_isGuestMode) {
      setState(() {
        _isLoading = true;
        _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
        _rawTimeoffDocs = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _combineTimeOff();
      });
    } else {
      setState(_combineTimeOff);
    }
  }

  void _navigateToAssign(Map<String, dynamic> doc) {
    if (_isGuestMode) {
      showGuestRestrictionDialog(context);
      return;
    }

    final limitReached = TimeOffService.isWorkerLimitReached(
      doc,
      _rawTimeoffDocs,
    );
    if (limitReached || doc['canAssignTimeOff'] == false) {
      _showTimeOffDataDialog(context, doc);
      return;
    }

    if (widget.onAssignTimeOff != null) {
      widget.onAssignTimeOff!(_docForNewLeave(doc));
    } else {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => AssignTimeOffScreen(
                onBack: () => Navigator.of(context).pop(),
                initialWorker: _docForNewLeave(doc),
              ),
            ),
          )
          .then((_) {
            if (_isGuestMode) _refreshGuestData();
          });
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

    final filtered = _displayWorkers;

    return Scaffold(
      backgroundColor: _kBg,
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
                    children: [
                      Text(
                        'time_off_list'.tr(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _kBlack,
                          fontFamily: _kFontFamily,
                        ),
                      ),
                      _buildRecordsFiltersAndExportRow(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    ScreenTableShimmer(
                      height: (MediaQuery.of(context).size.height - 329).clamp(
                        440.0,
                        1200.0,
                      ),
                      columnFlexes: const [3, 2, 2, 2],
                    )
                  else if (filtered.isEmpty)
                    _buildEmptyState()
                  else
                    _buildDataTable(filtered),
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
        color: _kWhite,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'workforce'.tr(),
                style: const TextStyle(
                  color: _kBlack,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: _kFontFamily,
                ),
              ),
              const SizedBox(height: 4),
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
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
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
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'search_workers_name_position'.tr(),
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
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
    final seen = <String>{};

    for (final w in _workersList) {
      final pos = (w['position'] ?? '').toString().trim();
      if (pos.isNotEmpty) {
        final key = pos.toLowerCase();
        if (seen.add(key)) actualPositions.add(pos);
      }
    }

    final positionsToShow = actualPositions.toList()..sort();
    for (final p in defaultPositions) {
      final alreadyIncluded = positionsToShow.any(
        (item) =>
            item.toLowerCase().contains(p.toLowerCase()) ||
            p.toLowerCase().contains(item.toLowerCase()),
      );
      if (!alreadyIncluded) positionsToShow.add(p);
    }

    final allFilters = ['All', ...positionsToShow];

    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            for (int i = 0; i < allFilters.length; i++) ...[
              _buildTabItem(
                allFilters[i],
                allFilters[i] == 'All'
                    ? 'all_filter'.tr()
                    : LocalizationHelper.localizePosition(allFilters[i]),
              ),
              if (i < allFilters.length - 1)
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

  Widget _buildTabItem(String filterKey, String displayLabel) {
    final isSelected = _selectedTab == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: isSelected ? _kWhite : _kBlack,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: _kFontFamily,
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> workers) {
    final tableHeight = (MediaQuery.of(context).size.height - 329)
        .clamp(440.0, 1200.0)
        .toDouble();

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
                _tableHeader('worker_name_header', flex: 3),
                _tableHeader('position', flex: 2),
                _tableHeader('contact_no', flex: 2),
                _tableHeader('time_off', flex: 2, padLeft: 8),
              ],
            ),
          ),
          const SizedBox(height: 1, child: ColoredBox(color: _kDivider)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: workers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildWorkerRow(workers[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String trKey, {int flex = 1, double padLeft = 0}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(right: padLeft == 0 ? 16 : 0, left: padLeft),
        child: Text(trKey.tr(), style: _kHeaderStyle),
      ),
    );
  }

  Widget _buildWorkerRow(Map<String, dynamic> doc) {
    final name = (doc['name'] ?? '').toString();
    final email = (doc['email'] ?? '').toString();
    final position = (doc['position'] ?? '').toString();
    final contact = _firstNonEmpty([
      doc['contact'],
      doc['phone'],
      doc['contactNo'],
      doc['phoneNumber'],
      doc['phoneNo'],
      doc['mobile'],
      doc['cell'],
    ]);
    final limitReached = TimeOffService.isWorkerLimitReached(
      doc,
      _rawTimeoffDocs,
    );
    final canAssign = doc['canAssignTimeOff'] != false;

    final displayAction = !canAssign
        ? (doc['status'] ??
                  doc['workerStatus'] ??
                  doc['employmentStatus'] ??
                  'Inactive')
              .toString()
              .toUpperCase()
        : (limitReached ? 'limit_reached'.tr() : 'assign'.tr());

    final actionColor = (!canAssign || limitReached) ? _kRed : _kActionBlue;

    return GestureDetector(
      onTap: () => _navigateToAssign(doc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    WorkerAvatar(
                      imageUrl: doc['profileImage']?.toString(),
                      name: name,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: _kBlack,
                              fontFamily: _kFontFamily,
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
                              fontFamily: _kFontFamily,
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
                padding: const EdgeInsets.only(right: 24),
                child: Text(
                  LocalizationHelper.localizePosition(position),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black,
                    fontFamily: _kFontFamily,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Text(
                  contact,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black,
                    fontFamily: _kFontFamily,
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
                  onTap: () => _navigateToAssign(doc),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  splashColor: _kActionBlue.withValues(alpha: 0.15),
                  highlightColor: _kActionBlue.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        displayAction,
                        style: TextStyle(
                          fontSize: 16,
                          color: actionColor,
                          fontWeight: FontWeight.w500,
                          fontFamily: _kFontFamily,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
  }

  Widget _buildEmptyState() {
    final height = (MediaQuery.of(context).size.height - 329)
        .clamp(440.0, 1200.0)
        .toDouble();
    final hasFilters = _isDropdownFilterActive;
    final filterName = _activeFilterName;

    final message = hasFilters
        ? (filterName.isNotEmpty
              ? 'no_records_named_filter'.tr(namedArgs: {'name': filterName})
              : 'no_records_selected_filter'.tr())
        : 'no_time_off_records'.tr();

    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/placeholder_workers.svg',
            width: 120,
            height: 100,
            colorFilter: const ColorFilter.mode(_kPlaceholder, BlendMode.srcIn),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kBlue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: _kFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsFiltersAndExportRow() {
    final match = _periodOptions.firstWhere(
      (e) => e['value'] == _recordsPeriodFilter,
      orElse: () => {
        'value': _recordsPeriodFilter,
        'label': _recordsPeriodFilter,
      },
    );

    var periodLabel = match['label']!;
    if (_recordsPeriodFilter == 'Custom Range' && _customDateRange != null) {
      final s = _customDateRange!.start;
      final e = _customDateRange!.end;

      if (s.year == e.year && s.month == e.month && s.day == e.day) {
        periodLabel = DateFormat('dd MMM').format(s);
      } else if (s.year == e.year) {
        periodLabel =
            '${DateFormat('dd MMM').format(s)} - ${DateFormat('dd MMM').format(e)}';
      } else {
        periodLabel =
            '${DateFormat('dd MMM yy').format(s)} - ${DateFormat('dd MMM yy').format(e)}';
      }
    }

    final leaveLabel = _recordsLeaveTypeFilter == 'All'
        ? 'all_filter'.tr()
        : _localizedLeaveType(_recordsLeaveTypeFilter);

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildFilterPopup<String>(
          value: _recordsPeriodFilter,
          label: periodLabel,
          icon: const Icon(
            Icons.calendar_month_rounded,
            size: 20,
            color: Colors.white,
          ),
          options: _periodOptions,
          onSelected: (val) {
            if (val == 'Custom Range') {
              _selectCustomDateRange(context);
            } else {
              setState(() {
                _recordsPeriodFilter = val;
                _customDateRange = null;
                _customSelectedDates = null;
              });
            }
          },
        ),
        _buildFilterPopup<String>(
          value: _recordsLeaveTypeFilter,
          label: leaveLabel,
          iconWidget: Image.asset(
            'assets/filter.png',
            width: 18,
            height: 18,
            color: _kWhite,
          ),
          options: _leaveTypeOptions,
          onSelected: (val) => setState(() => _recordsLeaveTypeFilter = val),
          maxWidth: 150,
          minWidth: 120,
        ),
        InkWell(
          onTap: _isExportingCsv ? null : _handleExportCsv,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _kGreen,
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
                Text('export_csv'.tr(), style: _kWhiteText16w500),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPopup<T>({
    required T value,
    required String label,
    Widget? icon,
    Widget? iconWidget,
    required List<Map<String, String>> options,
    required ValueChanged<String> onSelected,
    double minWidth = 140,
    double maxWidth = 220,
  }) {
    final hasLeading = icon != null || iconWidget != null;

    return PopupMenuButton<String>(
      tooltip: '',
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      onSelected: onSelected,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: _kWhite,
      elevation: 4,
      itemBuilder: (_) => options.map((f) {
        final selected = value.toString() == f['value'];

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
                    color: selected ? _kBlue : Colors.grey.shade300,
                    width: 2,
                  ),
                  color: selected ? _kBlue : Colors.transparent,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 10, color: _kWhite)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f['label']!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? _kBlue : _kBlack,
                    fontFamily: _kFontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _kBlue,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?icon,
            ?iconWidget,
            if (hasLeading) const SizedBox(width: 6),
            Text(label, style: _kWhiteText16w500),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeOffDataDialog(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final name = (data['name'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final notes = (data['notes'] ?? '').toString();
    final wId = (data['workerId'] ?? data['id'] ?? '').toString().trim();
    final normEmail = email.trim().toLowerCase();

    final workerRecords = _rawTimeoffDocs.where((d) {
      if (!TimeOffService.isActiveRecord(d)) return false;

      final rId = (d['workerId'] ?? '').toString().trim();
      final rEmail = (d['email'] ?? '').toString().trim().toLowerCase();

      return (wId.isNotEmpty && wId == rId) ||
          (normEmail.isNotEmpty && normEmail == rEmail);
    }).toList();

    final leaveDatesByType = TimeOffService.leaveDatesByTypeForWorker(
      data,
      workerRecords,
    );
    final totalDays = leaveDatesByType.values.fold<int>(
      0,
      (t, dates) => t + dates.length,
    );
    final selectedDays = totalDays.toString();

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth * 0.92 : 460.0;

    final allDatesWithTypes = <Map<String, dynamic>>[];
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
      barrierColor: _kBlue.withValues(alpha: 0.5),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: Container(
            width: dialogWidth,
            height: 420,
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
                _buildDialogHeader(dialogCtx),
                _buildWorkerPreviewHeader(
                  name: name,
                  email: email,
                  imageUrl: data['profileImage']?.toString(),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _kWhite,
                      border: Border(
                        left: BorderSide(color: _kCardBorder, width: 1.5),
                        right: BorderSide(color: _kCardBorder, width: 1.5),
                        bottom: BorderSide(color: _kCardBorder, width: 1.5),
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
                            builder: (_, constraints) {
                              final cardWidth = (constraints.maxWidth - 12) / 2;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMetricCard(
                                      icon: const Icon(
                                        Icons.event_available,
                                        color: _kDarkBlue,
                                        size: 20,
                                      ),
                                      title: 'total_leave_days'.tr(),
                                      value: selectedDays,
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMetricCard(
                                      icon: const Icon(
                                        Icons.calendar_month,
                                        color: _kDarkBlue,
                                        size: 20,
                                      ),
                                      title: 'requested_days'.tr(),
                                      value: selectedDays,
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMetricCard(
                                      icon: const Icon(
                                        Icons.beach_access,
                                        color: _kDarkBlue,
                                        size: 20,
                                      ),
                                      title: 'remaining_days'.tr(),
                                      value:
                                          '${TimeOffService.totalAvailableLeaves(data)}',
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMetricCard(
                                      icon: const Icon(
                                        Icons.date_range,
                                        color: _kDarkBlue,
                                        size: 20,
                                      ),
                                      title: 'selected_dates'.tr(),
                                      value: _formatDatesSummary(
                                        allDatesWithTypes,
                                      ),
                                      onTap: () => _showSelectedDatesDialog(
                                        dialogCtx,
                                        allDatesWithTypes,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMetricCard(
                                      icon: const Icon(
                                        Icons.notes,
                                        color: _kDarkBlue,
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
      final activeRecords = _rawTimeoffDocs.where((r) {
        if (!TimeOffService.isActiveRecord(r)) return false;
        final rId = (r['workerId'] ?? '').toString().trim();
        final rEmail = (r['email'] ?? '').toString().trim().toLowerCase();
        return (wId.isNotEmpty && wId == rId) ||
            (normEmail.isNotEmpty && normEmail == rEmail);
      }).toList();

      Map<String, dynamic>? latest;
      if (activeRecords.isNotEmpty) {
        latest = activeRecords.reduce((a, b) {
          final aId = (a['id'] ?? '').toString();
          final bId = (b['id'] ?? '').toString();
          return aId.compareTo(bId) >= 0 ? a : b;
        });
      }

      final merged = <String, dynamic>{...data};
      if (latest != null) merged.addAll(latest);

      if (widget.onAssignTimeOff != null) {
        widget.onAssignTimeOff!(merged);
      } else {
        setState(() {
          _isAssigningTimeOff = true;
          _workerForTimeOff = merged;
        });
      }
    }
  }

  Widget _buildDialogHeader(BuildContext context) {
    return Container(
      height: 40,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _kDarkBlue,
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
            child: const MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: _kWhite, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'assign_time_off'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: _kFontFamily,
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
                  colorFilter: const ColorFilter.mode(_kWhite, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
        color: _kWhite,
        border: Border(bottom: BorderSide(color: _kCardBorder)),
      ),
      child: Row(
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
                    color: _kGrey333,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: _kFontFamily,
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
                        _kGrey666,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(
                          color: _kGrey666,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          fontFamily: _kFontFamily,
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

  Widget _buildMetricCard({
    required Widget icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    final card = Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kCardBorder, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kLightBlue,
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
                    fontFamily: _kFontFamily,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _kBlack,
                    fontWeight: FontWeight.bold,
                    fontFamily: _kFontFamily,
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

    if (onTap == null) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }

  String _formatDatesSummary(List<Map<String, dynamic>> dates) {
    if (dates.isEmpty) return 'select_date'.tr();

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final visible = dates
        .take(3)
        .map((e) => fmt(e['date'] as DateTime))
        .join(', ');
    final remaining = dates.length - 3;
    return remaining > 0 ? '$visible +$remaining' : visible;
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

    final assignedByType = <String, Set<DateTime>>{
      for (final t in typeOrder) t: <DateTime>{},
    };

    for (final item in datesWithTypes) {
      final type = TimeOffService.normalizeLeaveType(
        (item['type'] ?? '').toString(),
      );
      final date = item['date'];
      if (date is DateTime && assignedByType.containsKey(type)) {
        assignedByType[type]!.add(DateTime(date.year, date.month, date.day));
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
            color: _kWhite,
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
                decoration: const BoxDecoration(color: _kDarkBlue),
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
                          fontFamily: _kFontFamily,
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
                color: _kBg,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: typeOrder.map((type) {
                    final color = LeaveColors.getColor(type);
                    final count = assignedByType[type]!.length;

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
                        '$count ${count == 1 ? 'day'.tr() : 'days'.tr()}',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: _kFontFamily,
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
                      ? _buildNoDatesPlaceholder()
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          itemCount: datesWithTypes.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: _kBorder),
                          itemBuilder: (context, index) {
                            final item = datesWithTypes[index];
                            final date = item['date'] as DateTime;
                            final type = item['type'] as String?;
                            final effectiveType = (type?.isNotEmpty == true)
                                ? type
                                : leaveType;
                            final displayType = effectiveType == null
                                ? ''
                                : _localizedLeaveType(effectiveType);
                            final locale = context.locale.toString();

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: _kLightBlue,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: _kDarkBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: _kFontFamily,
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
                                          DateFormat.yMMMd(locale).format(date),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                            fontFamily: _kFontFamily,
                                          ),
                                        ),
                                        Text(
                                          DateFormat.EEEE(locale).format(date),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _kGrey666,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: _kFontFamily,
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
                                          fontFamily: _kFontFamily,
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

  Widget _buildNoDatesPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
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
                fontFamily: _kFontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _dateAtPosition(Offset position, DateTime monthDate) {
    const cellWidth = 48.0;
    const cellHeight = 48.0;
    const headerHeight = 30.0;

    final col = (position.dx / cellWidth).floor();
    final row = ((position.dy - headerHeight) / cellHeight).floor();

    if (col < 0 || col > 6 || row < 0) return null;

    final first = DateTime(monthDate.year, monthDate.month, 1);
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final startOffset = first.weekday % 7;
    final day = (row * 7) + col - startOffset + 1;

    if (day < 1 || day > daysInMonth) return null;
    return DateTime(monthDate.year, monthDate.month, day);
  }

  Widget _buildCalendarGrid(
    DateTime calendarDate,
    Set<DateTime> selectedDates,
  ) {
    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    final first = DateTime(calendarDate.year, calendarDate.month, 1);
    final daysInMonth = DateTime(
      calendarDate.year,
      calendarDate.month + 1,
      0,
    ).day;
    final startOffset = first.weekday % 7;
    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekdays
              .map(
                (day) => SizedBox(
                  width: 44,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kBlue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: _kFontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 48,
          ),
          itemCount: totalCells,
          itemBuilder: (_, index) {
            final dayNum = index - startOffset + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const SizedBox();
            }

            final cellDate = DateTime(
              calendarDate.year,
              calendarDate.month,
              dayNum,
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
                color: isSelected ? _kBlue : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? _kBlue : const Color(0xFFE2E8F0),
                ),
              ),
              child: Center(
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black,
                    fontFamily: _kFontFamily,
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
    var calendarDate = DateTime.now();
    var selectedDates = <DateTime>{};

    if (_recordsPeriodFilter == 'Custom Range') {
      if (_customSelectedDates != null && _customSelectedDates!.isNotEmpty) {
        selectedDates = Set<DateTime>.from(_customSelectedDates!);
        calendarDate = _customSelectedDates!.first;
      } else if (_customDateRange != null) {
        for (
          var d = _customDateRange!.start;
          !d.isAfter(_customDateRange!.end);
          d = d.add(const Duration(days: 1))
        ) {
          selectedDates.add(DateTime(d.year, d.month, d.day));
        }
        calendarDate = _customDateRange!.start;
      }
    }

    DateTime? dragAnchor;
    Offset? dragStart;
    var dragMoved = false;
    var beforeDrag = <DateTime>{};

    final result = await showDialog<List<DateTime>?>(
      context: context,
      barrierColor: _kBlue.withValues(alpha: 0.5),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: _kWhite,
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
                                color: _kBlack,
                                fontFamily: _kFontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 22),
                          onPressed: () => setModalState(() {
                            calendarDate = DateTime(
                              calendarDate.year,
                              calendarDate.month - 1,
                            );
                          }),
                        ),
                        Text(
                          DateFormat(
                            'MMMM yyyy',
                          ).format(calendarDate).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: _kFontFamily,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 22),
                          onPressed: () => setModalState(() {
                            calendarDate = DateTime(
                              calendarDate.year,
                              calendarDate.month + 1,
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Listener(
                      onPointerDown: (e) {
                        dragAnchor = _dateAtPosition(
                          e.localPosition,
                          calendarDate,
                        );
                        dragStart = e.localPosition;
                        dragMoved = false;
                        beforeDrag = Set<DateTime>.from(selectedDates);
                        setModalState(() {});
                      },
                      onPointerMove: (e) {
                        if (dragStart != null && !dragMoved) {
                          final dx = (e.localPosition.dx - dragStart!.dx).abs();
                          final dy = (e.localPosition.dy - dragStart!.dy).abs();
                          if (dx > 5 || dy > 5) dragMoved = true;
                        }
                        if (!dragMoved || dragAnchor == null) return;

                        final current = _dateAtPosition(
                          e.localPosition,
                          calendarDate,
                        );
                        if (current == null) return;

                        setModalState(() {
                          selectedDates
                            ..clear()
                            ..addAll(beforeDrag);

                          final removing = beforeDrag.contains(dragAnchor);
                          final start = dragAnchor!.isBefore(current)
                              ? dragAnchor!
                              : current;
                          final end = dragAnchor!.isAfter(current)
                              ? dragAnchor!
                              : current;

                          for (
                            var d = start;
                            !d.isAfter(end);
                            d = d.add(const Duration(days: 1))
                          ) {
                            if (removing) {
                              selectedDates.remove(d);
                            } else {
                              selectedDates.add(d);
                            }
                          }
                        });
                      },
                      onPointerUp: (_) {
                        if (!dragMoved && dragAnchor != null) {
                          final date = dragAnchor!;
                          setModalState(() {
                            final exists = selectedDates.any(
                              (d) =>
                                  d.year == date.year &&
                                  d.month == date.month &&
                                  d.day == date.day,
                            );

                            if (exists) {
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

                        dragAnchor = null;
                        dragStart = null;
                        dragMoved = false;
                        beforeDrag = <DateTime>{};
                        setModalState(() {});
                      },
                      child: _buildCalendarGrid(calendarDate, selectedDates),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedDates.isEmpty
                              ? const Color(0xFFE2E8F0)
                              : _kBlue,
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
                                final sorted = selectedDates.toList()..sort();
                                Navigator.of(context).pop(sorted);
                              },
                        child: Text(
                          'apply'.tr(),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: _kFontFamily,
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
        _customSelectedDates = result.toSet();
        _customDateRange = DateTimeRange(start: result.first, end: result.last);
        _recordsPeriodFilter = 'Custom Range';
      });
    }
  }

  Future<void> _handleExportCsv() async {
    if (_isExportingCsv) return;

    if (_isGuestMode) {
      showGuestRestrictionDialog(context);
      return;
    }

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
      if (mounted) {
        setState(() => _isExportingCsv = false);
      }
    }
  }

  Future<void> _exportTimeOffCsv(List<Map<String, dynamic>> records) async {
    final periodLabel =
        _recordsPeriodFilter == 'Custom Range' && _customDateRange != null
        ? '${DateFormat('dd MMM yyyy').format(_customDateRange!.start)} - '
              '${DateFormat('dd MMM yyyy').format(_customDateRange!.end)}'
        : _recordsPeriodFilter;

    final defaultFileName =
        'time_off_${periodLabel.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.csv';

    final savedPath = await TimeOffExportService.exportCsv(
      records: records,
      fileName: defaultFileName,
    );

    if (savedPath != null && mounted) {
      final savedName = savedPath.split('/').last;
      FlashySnackBar.show(
        context,
        message: 'file_saved_and_opened'.tr(namedArgs: {'file': savedName}),
      );
    }
  }
}
