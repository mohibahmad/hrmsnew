import 'dart:async';
import 'dart:ui' as ui;
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';
import '../../widgets/unsaved_changes_dialog.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/auth_service.dart';
import '../../services/dummy_data.dart';
import '../../services/error_reporter.dart';
import '../../services/firestore_service.dart';
import '../../services/preferences_service.dart';
import '../../services/time_off_service.dart';
import '../../utils/utils.dart';
import '../../widgets/clickable_gesture_detector.dart';
import '../../widgets/notification_bell.dart';

class AssignTimeOffScreen extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;
  final Map<String, dynamic>? initialWorker;
  final bool viewOnly;

  const AssignTimeOffScreen({
    super.key,
    required this.onBack,
    this.onProfileTap,
    this.onNotificationTap,
    this.initialWorker,
    this.viewOnly = false,
  });

  @override
  ConsumerState<AssignTimeOffScreen> createState() => AssignTimeOffScreenState();
}

class LeaveColors {
  const LeaveColors._();

  static const Color annual = Color(0xFFF59E0B);
  static const Color annualBg = Color(0xFFFFFBEB);
  static const Color sick = Color(0xFFEF4444);
  static const Color sickBg = Color(0xFFFEF2F2);
  static const Color casual = Color(0xFF3B82F6);
  static const Color casualBg = Color(0xFFEFF6FF);
  static const Color medical = Color(0xFF10B981);
  static const Color medicalBg = Color(0xFFECFDF5);

  static const Color _annualText = Color(0xFFD97706);
  static const Color _sickText = Color(0xFFDC2626);
  static const Color _casualText = Color(0xFF1D4ED8);
  static const Color _medicalText = Color(0xFF047857);
  static const Color _defaultText = Color(0xFF1E293B);

  static Color getColor(String leaveType) {
    final lower = leaveType.toLowerCase().trim();
    if (lower.contains('annual')) return annual;
    if (lower.contains('sick')) return sick;
    if (lower.contains('casual')) return casual;
    if (lower.contains('medical')) return medical;
    return casual;
  }

  static Color getTextColor(String leaveType) {
    final lower = leaveType.toLowerCase().trim();
    if (lower.contains('annual')) return _annualText;
    if (lower.contains('sick')) return _sickText;
    if (lower.contains('casual')) return _casualText;
    if (lower.contains('medical')) return _medicalText;
    return _defaultText;
  }

  static Color getBgColor(String leaveType) {
    final lower = leaveType.toLowerCase().trim();
    if (lower.contains('annual')) return annualBg;
    if (lower.contains('sick')) return sickBg;
    if (lower.contains('casual')) return casualBg;
    if (lower.contains('medical')) return medicalBg;
    return getColor(leaveType).withValues(alpha: 0.15);
  }
}

class AssignTimeOffScreenState extends ConsumerState<AssignTimeOffScreen> {
  static const List<Map<String, String>> _leaveTypeOptions = [
    {'value': 'Annual Leave', 'labelKey': 'annual_leave'},
    {'value': 'Sick Leave', 'labelKey': 'sick_leave_type'},
    {'value': 'Casual Leave', 'labelKey': 'casual_leave_type'},
    {'value': 'Medical Leave', 'labelKey': 'medical_leave_type'},
  ];

  static const Set<String> _paidLeaveTypes = {
    'Annual Leave',
    'Sick Leave',
    'Casual Leave',
    'Medical Leave',
  };

  static const double _calendarContentWidth = 7 * 50 + 6 * 4;

  static const Set<String> _inactiveStatuses = {
    'inactive',
    'terminated',
    'deleted',
    'archived',
  };

  static const List<String> _weekdayKeys = [
    'weekday_sun',
    'weekday_mon',
    'weekday_tue',
    'weekday_wed',
    'weekday_thu',
    'weekday_fri',
    'weekday_sat',
  ];

  static const List<String> _legendTypes = [
    'Annual Leave',
    'Sick Leave',
    'Casual Leave',
    'Medical Leave',
  ];

  static const List<Color> _legendColors = [
    LeaveColors.annual,
    LeaveColors.sick,
    LeaveColors.casual,
    LeaveColors.medical,
  ];

  static const double _cellExtent = 54.0;
  static const double _calendarWidth = 7 * _cellExtent;
  static const double _containerWidth = _calendarWidth + 32;
  static const double _calendarOuterWidth = _calendarContentWidth + 32.0 + 2.0;
  static const double _naturalRowWidth = _calendarOuterWidth * 2 + 24.0;
  static const double _headerHeight = 93.0;
  static const double _calendarPadding = 17.0;

  late AuthService _authService;
  late FirestoreService _firestore;

  bool _isLoading = false;
  String _timeOffType = 'Annual Leave';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  DateTime _calendarMonth = DateTime.now();
  DateTime _calendarMonth2 = DateTime.now();
  Set<DateTime> _selectedDates = <DateTime>{};
  DateTime? _dragAnchorDate;
  DateTime? _lastDragDate;
  Set<DateTime> _selectionBeforeDrag = <DateTime>{};
  bool _dragExceededAvailableDays = false;
  Offset? _dragStartPosition;
  bool _dragMoved = false;

  final TextEditingController _notesController = TextEditingController();
  String? _editingId;

  List<Map<String, dynamic>> _workers = const [];
  Map<String, dynamic>? _selectedWorker;

  StreamSubscription? _workersSub;
  StreamSubscription? _timeoffSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _holidaysSub;

  String _watchedTimeoffWorkerId = '';
  List<Map<String, dynamic>> _timeoffRecords = const [];

  Map<String, dynamic>? _editingRecord;
  List<Map<String, dynamic>> _holidays = const [];
  Set<int> _companyWorkingDays = const {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };

  bool _initialized = false;
  bool _hasTypeChanged = false;
  bool _hasDateSelectionChanged = false;
  bool _hasNotesChanged = false;
  bool _isAggregateOverview = false;
  bool _bypassingConfirm = false;

  final Map<String, PendingTimeOffDraft> _pendingDrafts = {};

  Map<DateTime, String>? _cachedDateToTypeMap;
  bool _dateToTypeMapDirty = true;
  final Set<DateTime> _deselectedDates = {};

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  bool get _isPaidLeave => _paidLeaveTypes.contains(_timeOffType);

  bool get _usesPaidAllowance => _isGuest || _isPaidLeave;

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  bool get _hasUnsavedChanges =>
      _currentHasUnsavedChanges ||
      _pendingDrafts.values.any((draft) => draft.hasChanges);

  bool get _currentHasUnsavedChanges => hasUnsavedTimeOffChanges(
        hasSelectedDates: _hasDateSelectionChanged,
        hasNotes: _hasNotesChanged,
        isEditing: _editingId != null,
        typeChanged: _hasTypeChanged,
        datesChanged: _hasDateSelectionChanged,
      );

  Map<String, dynamic> get _selectedWorkerForService {
    final worker = _selectedWorker;
    if (worker == null || _isGuest) return worker ?? const <String, dynamic>{};

    final workerId =
        (worker['workerId'] ?? worker['id'] ?? '').toString().trim();
    if (workerId.isEmpty) return worker;

    return {...worker, 'id': workerId, 'workerId': workerId};
  }

  @override
  void initState() {
    super.initState();
    _resetForWorker(widget.initialWorker);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    _loadWorkers();
  }

  @override
  void didUpdateWidget(covariant AssignTimeOffScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameInitialSelection(widget.initialWorker, oldWidget.initialWorker)) {
      _resetForWorker(widget.initialWorker);
      _loadTimeoffForSelectedWorker();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _workersSub?.cancel();
    _timeoffSub?.cancel();
    _attendanceSub?.cancel();
    _holidaysSub?.cancel();
    super.dispose();
  }

  void _invalidateDateTypeMap() {
    _dateToTypeMapDirty = true;
    _cachedDateToTypeMap = null;
  }

  DateTime _dateOnly(DateTime d) => dateOnly(d);

  String _dateOnlyString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _getMonthName(int month) =>
      DateFormat('MMMM', context.locale.toString()).format(DateTime(2024, month));

  bool _sameWorker(Map<String, dynamic> first, Map<String, dynamic> second) =>
      WorkerIdentity.samePerson(first, second);

  bool _isValidLeaveType(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return false;

    final normalized = TimeOffService.normalizeLeaveType(raw);
    return _leaveTypeOptions.any((option) => option['value'] == normalized);
  }

  bool _isTimeOffRecord(Map<String, dynamic> data) {
    final hasValidType =
        _isValidLeaveType(data['type']) || _isValidLeaveType(data['action']);

    final hasDateData = data.containsKey('selectedDates') ||
        data.containsKey('startDate') ||
        data.containsKey('endDate');

    return hasValidType && hasDateData;
  }

  String _leaveTypeFromRecord(Map<String, dynamic> data) {
    if (_isValidLeaveType(data['type'])) {
      return TimeOffService.normalizeLeaveType(data['type'].toString());
    }
    if (_isValidLeaveType(data['action'])) {
      return TimeOffService.normalizeLeaveType(data['action'].toString());
    }
    return 'Annual Leave';
  }

  String? _timeOffRecordId(Map<String, dynamic>? record) {
    if (record == null) return null;
    for (final key in const ['timeOffId', 'timeoffId', 'id']) {
      final value = record[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  bool _sameInitialSelection(
      Map<String, dynamic>? first, Map<String, dynamic>? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;

    final firstId =
        (first['id'] ?? first['workerId'] ?? '').toString().trim();
    final secondId =
        (second['id'] ?? second['workerId'] ?? '').toString().trim();
    final firstAction =
        (first['action'] ?? first['type'] ?? '').toString().trim();
    final secondAction =
        (second['action'] ?? second['type'] ?? '').toString().trim();

    return firstId == secondId &&
        firstAction == secondAction &&
        _sameWorker(first, second);
  }

  bool _isEligibleWorker(Map<String, dynamic> worker) {
    final status = (worker['employmentStatus'] ??
            worker['workerStatus'] ??
            worker['status'] ??
            'Active')
        .toString()
        .trim()
        .toLowerCase();
    return !_inactiveStatuses.contains(status);
  }

  String _getWorkerPhone(Map<String, dynamic> w) {
    for (final key in const ['phone', 'contact']) {
      final val = w[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        return val.toString().trim();
      }
    }
    return '';
  }

  void _resetForWorker(Map<String, dynamic>? worker) {
    _editingRecord = null;
    _editingId = null;
    _isAggregateOverview = false;
    _bypassingConfirm = false;

    if (worker == null) {
      _selectedWorker = null;
      _resetFormFields();
      return;
    }

    _isAggregateOverview = worker['_aggregateTimeOffEdit'] == true;

    if (!_isAggregateOverview && _isTimeOffRecord(worker)) {
      _editingRecord = Map<String, dynamic>.from(worker);
      _editingId = _timeOffRecordId(worker);
      _selectedWorker = _findMatchingWorker(worker);
    } else {
      _selectedWorker = worker;
    }

    _resetFormFields();
  }

  void _resetFormFields() {
    _pendingDrafts.clear();
    _deselectedDates.clear();
    _invalidateDateTypeMap();
    final source = _editingRecord ?? _selectedWorker;
    _hasTypeChanged = false;
    _hasDateSelectionChanged = false;
    _hasNotesChanged = false;

    if (_isAggregateOverview && source != null) {
      _editingRecord = null;
      _editingId = null;
      _timeOffType = 'Annual Leave';

      final aggregateDates = source['_aggregateDatesByType'];
      final datesForType =
          aggregateDates is Map ? aggregateDates[_timeOffType] : null;
      _selectedDates = datesForType is Iterable
          ? datesForType
              .map(TimeOffService.parseDate)
              .whereType<DateTime>()
              .toSet()
          : <DateTime>{};

      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
      _calendarMonth2 =
          DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
      _notesController.clear();
    } else if (source != null && _isTimeOffRecord(source)) {
      _editingId =
          _timeOffRecordId(_editingRecord) ?? _timeOffRecordId(source);
      _timeOffType = _leaveTypeFromRecord(source);
      _selectedDates = TimeOffService.selectedDatesForRecord(source)
          .map(_dateOnly)
          .toSet();

      if (_selectedDates.isNotEmpty) {
        _syncSelectionBounds();
      } else {
        _startDate = DateTime.now();
        _endDate = DateTime.now();
      }

      _notesController.text = source['notes']?.toString() ?? '';
    } else {
      _editingId = null;
      _selectedDates = <DateTime>{};
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _timeOffType = 'Annual Leave';
      _notesController.clear();
    }

    if (_selectedDates.isNotEmpty && !_isAggregateOverview) {
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
      _calendarMonth2 =
          DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
    }

    _timeOffType = TimeOffService.normalizeLeaveType(_timeOffType);

    if (!_leaveTypeOptions.any((o) => o['value'] == _timeOffType)) {
      _timeOffType = 'Annual Leave';
    }

    if (!_isAggregateOverview) {
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
      _calendarMonth2 =
          DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);

      // Only jump to the current month when starting fresh (no dates yet).
      // When editing an existing record the calendar must open on the
      // record's own month — even if it's in the past.
      if (_selectedDates.isEmpty) {
        final now = DateTime.now();
        final currentMonth = DateTime(now.year, now.month, 1);
        if (_calendarMonth.isBefore(currentMonth)) {
          _calendarMonth = currentMonth;
          _calendarMonth2 = DateTime(currentMonth.year, currentMonth.month + 1, 1);
        }
      }
    }
  }

  void _markFormClean() {
    _hasTypeChanged = false;
    _hasDateSelectionChanged = false;
    _hasNotesChanged = false;
  }

  List<DateTime> get _sortedSelectedDates => _selectedDates.toList()..sort();

  void _syncSelectionBounds() {
    final dates = _sortedSelectedDates;
    if (dates.isEmpty) return;
    _startDate = dates.first;
    _endDate = dates.last;
  }

  PendingTimeOffDraft _currentDraft() => PendingTimeOffDraft(
        leaveType: _timeOffType,
        editingId: _editingId,
        editingRecord: _editingRecord == null
            ? null
            : Map<String, dynamic>.from(_editingRecord!),
        selectedDates: Set<DateTime>.from(_selectedDates),
        notes: _notesController.text.trim(),
        typeChanged: _hasTypeChanged,
        datesChanged: _hasDateSelectionChanged,
        notesChanged: _hasNotesChanged,
      );

  String _draftKeyFor(String? editingId, String leaveType) {
    final id = (editingId ?? '').trim();
    return id.isNotEmpty ? id : leaveType;
  }

  void _stashCurrentDraft() {
    final draft = _currentDraft();
    final key = _draftKeyFor(_editingId, _timeOffType);
    if (draft.hasChanges) {
      _pendingDrafts[key] = draft;
    } else {
      _pendingDrafts.remove(key);
    }
  }

  Map<DateTime, String> get _selectedDateToTypeMap {
    if (!_dateToTypeMapDirty && _cachedDateToTypeMap != null) {
      return _cachedDateToTypeMap!;
    }

    final map = <DateTime, String>{};
    final normType = TimeOffService.normalizeLeaveType(_timeOffType);
    for (final d in _selectedDates) {
      map[_dateOnly(d)] = normType;
    }
    for (final draft in _pendingDrafts.values) {
      final draftNormType = TimeOffService.normalizeLeaveType(draft.leaveType);
      for (final d in draft.selectedDates) {
        map[_dateOnly(d)] = draftNormType;
      }
    }

    _cachedDateToTypeMap = map;
    _dateToTypeMapDirty = false;
    return map;
  }

  Map<String, dynamic>? _holidayForDate(DateTime date) {
    for (final holiday in _holidays) {
      if (holiday['isEnabled'] == false) continue;
      final storedDate =
          AppDateUtils.holidayRecordDate(holiday, fallbackYear: date.year);
      if (storedDate == null ||
          storedDate.day != date.day ||
          storedDate.month != date.month) continue;
      if (_isGuest) return holiday;

      final isRecurring = holiday['isRecurring'] == true;
      final holidayYear = storedDate.year;
      if (isRecurring || holidayYear == 0 || holidayYear == date.year) {
        return holiday;
      }
    }
    return null;
  }

  bool _isNonWorkingDate(DateTime date) =>
      !_companyWorkingDays.contains(date.weekday) ||
      _holidayForDate(date) != null;

  int get _selectedDaysCount => _selectedDates.length;

  int _baseAvailableDaysForType(String type) {
    if (_selectedWorker == null) return 0;

    final base = TimeOffService.availableBalanceForEditingRecord(
      _selectedWorkerForService,
      _timeoffRecords,
      type,
      _editingRecord,
    );

    if (!_isAggregateOverview) return base;

    final assignedDates = TimeOffService.assignedLeaveDatesForWorkerByType(
          _selectedWorkerForService,
          _timeoffRecords,
        )[TimeOffService.normalizeLeaveType(type)]
            ?.length ??
        0;
    final limit = TimeOffService.configuredLimitForType(
        _selectedWorkerForService, type);
    return (base + assignedDates).clamp(0, limit);
  }

  int _availableDaysForType(String type) {
    if (widget.viewOnly) {
      return TimeOffService.remainingForType(
          _selectedWorkerForService, _timeoffRecords, type);
    }

    final base = _baseAvailableDaysForType(type);
    final normType = TimeOffService.normalizeLeaveType(type);
    final dateTypeMap = _selectedDateToTypeMap;
    int currentlySelected = 0;
    for (final t in dateTypeMap.values) {
      if (TimeOffService.normalizeLeaveType(t) == normType) {
        currentlySelected++;
      }
    }

    int deselectedSavedForType = 0;
    for (final d in _deselectedDates) {
      final leave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: d,
      );
      if (leave != null &&
          TimeOffService.normalizeLeaveType(
                  (leave['action'] ?? leave['type']).toString()) ==
              normType) {
        deselectedSavedForType++;
      }
    }

    return projectedTimeOffBalance(
        availableDays: base + deselectedSavedForType,
        requestedDays: currentlySelected);
  }

  int get _baseAvailableDays => _baseAvailableDaysForType(_timeOffType);

  int get _availableDays => _availableDaysForType(_timeOffType);

  bool get _requestedDaysExceedAvailable =>
      !widget.viewOnly &&
      _usesPaidAllowance &&
      _selectedDaysCount > _baseAvailableDays;

  String get _localizedSelectedLeaveType {
    final normalized = TimeOffService.normalizeLeaveType(_timeOffType);
    final option =
        _leaveTypeOptions.cast<Map<String, String>?>().firstWhere(
              (item) => item?['value'] == normalized,
              orElse: () => null,
            );
    return option?['labelKey']?.tr() ?? normalized;
  }

  String get _availableLeaveLabel {
    return switch (TimeOffService.normalizeLeaveType(_timeOffType)) {
      'Annual Leave' => 'total_annual_leave_days'.tr(),
      'Sick Leave' => 'total_sick_leave_days'.tr(),
      'Casual Leave' => 'total_casual_leave_days'.tr(),
      'Medical Leave' => 'total_medical_leave_days'.tr(),
      _ => 'total_leave_days'.tr(),
    };
  }

  int get _displayedLeaveBalance {
    if (_selectedWorker == null) return 0;
    return TimeOffService.configuredLimitForType(
        _selectedWorkerForService, _timeOffType);
  }

  String get _insufficientBalanceMessage {
    final availableDays = _availableDays;
    final key = availableDays == 0
        ? 'no_leave_days_available'
        : availableDays == 1
            ? 'only_one_leave_day_available'
            : 'only_leave_days_available';
    return key.tr(namedArgs: {
      'count': '$availableDays',
      'type': _localizedSelectedLeaveType,
    });
  }

  int get _requestedDays => widget.viewOnly
      ? _selectedDaysCount
      : (_requestedDaysExceedAvailable ? 0 : _selectedDaysCount);

  int get _summaryRequestedDays {
    if (_selectedWorker == null) return 0;
    if (_isAggregateOverview) return _selectedDaysCount;
    final normType = TimeOffService.normalizeLeaveType(_timeOffType);
    int deselectedSavedCount = 0;
    for (final d in _deselectedDates) {
      final leave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: d,
      );
      if (leave != null &&
          TimeOffService.normalizeLeaveType(
                  (leave['action'] ?? leave['type']).toString()) ==
              normType) {
        deselectedSavedCount++;
      }
    }
    final projected = TimeOffService.projectedAssignedDaysForEditingRecord(
      _selectedWorkerForService,
      _timeoffRecords,
      _timeOffType,
      _editingRecord,
      _selectedDaysCount,
    );
    return (projected - deselectedSavedCount).clamp(0, projected);
  }

  int get _remainingDaysAfterRequest {
    if (_selectedWorker == null) return 0;
    return (_displayedLeaveBalance - _summaryRequestedDays).clamp(0, 9999);
  }

  String get _currentSelectedDatesSummary {
    final dates = _sortedSelectedDates;
    if (dates.isEmpty) return 'select_date'.tr();

    final typeLabel = LocalizationHelper.localizeLeaveType(_timeOffType);
    final buffer = StringBuffer();
    final count = dates.length;
    final visible = count < 3 ? count : 3;

    for (int i = 0; i < visible; i++) {
      if (i > 0) buffer.write(', ');
      buffer.write('$typeLabel ${_formatDate(dates[i])}');
    }

    final remaining = count - 3;
    if (remaining > 0) {
      buffer.write(' +$remaining');
    }
    return buffer.toString();
  }

  void _loadWorkers() {
    if (_isGuest) {
      _loadGuestWorkers();
    } else {
      _loadFirestoreWorkers();
    }
  }

  void _loadGuestWorkers() {
    PreferencesService.getCompanyWorkingDays().then((days) {
      if (mounted) setState(() => _companyWorkingDays = days);
    });

    setState(() {
      _workers = DummyData.workers;
      _timeoffRecords = DummyData.timeoff;
      _holidays = DummyData.holidays.values
          .expand((records) => records)
          .cast<Map<String, dynamic>>()
          .toList();
      _selectedWorker = _resolveSelectedWorker();
    });
  }

  void _loadFirestoreWorkers() {
    _workersSub = _firestore.workersStream.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _workers = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        _selectedWorker = _resolveSelectedWorker();

        if (_editingRecord != null) {
          _editingId = _timeOffRecordId(_editingRecord);
        }
      });
      _loadTimeoffForSelectedWorker();
    }, onError: (_) {});

    _holidaysSub = _firestore.holidaysStream.listen((snapshot) {
      if (!mounted) return;

      final holidays = <Map<String, dynamic>>[];
      var workingDays = _companyWorkingDays;

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        if (data['type'] == 'company_work_days') {
          final savedDays = (data['workingDays'] as List<dynamic>? ?? [])
              .whereType<num>()
              .map((day) => day.toInt())
              .where(
                  (day) => day >= DateTime.monday && day <= DateTime.sunday)
              .toSet();
          if (savedDays.isNotEmpty) workingDays = savedDays;
          continue;
        }
        holidays.add({...data, 'id': doc.id});
      }

      setState(() {
        _holidays = holidays;
        _companyWorkingDays = workingDays;
      });
    }, onError: (_) {});
  }

  Map<String, dynamic>? _resolveSelectedWorker() {
    if (widget.initialWorker != null) {
      final match = _findMatchingWorker(widget.initialWorker!);
      if (match != null) return match;

      if (_isTimeOffRecord(widget.initialWorker!)) return null;
      return widget.initialWorker!;
    }

    if (_workers.isEmpty || _selectedWorker == null) return null;

    final idx = _workers.indexWhere((w) => _sameWorker(w, _selectedWorker!));
    return idx != -1 ? _workers[idx] : null;
  }

  Map<String, dynamic>? _findMatchingWorker(Map<String, dynamic> target) =>
      WorkerIdentity.findMatchingWorker(target, _workers);

  Future<void> _loadTimeoffForSelectedWorker() async {
    final worker = _selectedWorker;
    if (worker == null) {
      await _cancelTimeoffSubscriptions();
      if (mounted) {
        setState(() => _timeoffRecords = const []);
      }
      return;
    }

    final workerId =
        (worker['workerId'] ?? worker['id'] ?? '').toString().trim();
    if (workerId.isEmpty) {
      await _cancelTimeoffSubscriptions();
      if (mounted) {
        setState(() => _timeoffRecords = const []);
      }
      return;
    }

    if (_isGuest) {
      _loadGuestTimeoff(workerId);
      return;
    }

    if (_watchedTimeoffWorkerId == workerId &&
        _timeoffSub != null &&
        _attendanceSub != null) {
      if (mounted) setState(_syncRecordsAfterUpdate);
      return;
    }

    await _cancelTimeoffSubscriptions();
    if (!mounted) return;

    setState(() => _timeoffRecords = const []);
    _watchedTimeoffWorkerId = workerId;

    List<Map<String, dynamic>> latestTimeoffDocs = const [];
    List<Map<String, dynamic>> latestAttendanceDocs = const [];

    void updateCombined() {
      if (!mounted || _watchedTimeoffWorkerId != workerId) return;
      setState(() {
        _timeoffRecords = TimeOffService.combineTimeOffAndAttendanceRecords(
          timeOffRecords: latestTimeoffDocs,
          attendanceRecords: latestAttendanceDocs,
        );
        _invalidateDateTypeMap();
        _syncRecordsAfterUpdate();
      });
    }

    _timeoffSub = _firestore.timeoffForWorkerStream(workerId).listen(
      (snapshot) {
        latestTimeoffDocs = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        updateCombined();
      },
      onError: (Object error, StackTrace stack) {
        ErrorReporter.report(error, stack,
            context: 'TimeoffStream:$workerId');
      },
    );

    _attendanceSub = _firestore.attendanceStreamForWorker(workerId).listen(
      (snapshot) {
        latestAttendanceDocs = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        updateCombined();
      },
      onError: (Object error, StackTrace stack) {
        ErrorReporter.report(error, stack,
            context: 'AttendanceStream:$workerId');
      },
    );
  }

  void _loadGuestTimeoff(String workerId) {
    final rawTimeoff = DummyData.timeoff
        .where(
            (r) => (r['workerId'] ?? r['id'] ?? '').toString() == workerId)
        .map((r) {
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        final syntheticId =
            'timeoff_${r['workerId']}_${r['type']}_${r['startDate']}';
        r['id'] = syntheticId;
        return {...r, 'id': syntheticId};
      }
      return r;
    }).toList();

    final rawAttendance = DummyData.attendance
        .where(
            (r) => (r['workerId'] ?? r['id'] ?? '').toString() == workerId)
        .toList();

    final records = TimeOffService.combineTimeOffAndAttendanceRecords(
      timeOffRecords: rawTimeoff,
      attendanceRecords: rawAttendance,
    );

    if (mounted) {
      setState(() {
        _timeoffRecords = records;
        _invalidateDateTypeMap();
        _syncViewOnlyDatesForType();
      });
    }
  }

  Future<void> _cancelTimeoffSubscriptions() async {
    await _timeoffSub?.cancel();
    await _attendanceSub?.cancel();
    _timeoffSub = null;
    _attendanceSub = null;
    _watchedTimeoffWorkerId = '';
  }

  void _syncRecordsAfterUpdate() {
    if (widget.viewOnly) {
      _syncViewOnlyDatesForType();
    } else if (_isAggregateOverview) {
      _syncAggregateDatesForType();
    } else {
      _syncOpenRecordFromLiveData();
    }
  }

  void _syncViewOnlyDatesForType() {
    if (!widget.viewOnly || _selectedWorker == null) return;
    final datesByType = TimeOffService.leaveDatesByTypeForWorker(
      _selectedWorkerForService,
      _timeoffRecords,
    );
    _selectedDates =
        (datesByType[_timeOffType] ?? const <DateTime>[]).toSet();
    _invalidateDateTypeMap();
    _syncSelectionBounds();
  }

  void _syncAggregateDatesForType() {
    if (!_isAggregateOverview || _selectedWorker == null) return;
    final datesByType = TimeOffService.leaveDatesByTypeForWorker(
      _selectedWorkerForService,
      _timeoffRecords,
    );
    _selectedDates =
        (datesByType[_timeOffType] ?? const <DateTime>[]).toSet();
    _editingRecord = null;
    _editingId = null;
    _notesController.clear();
    _invalidateDateTypeMap();
    _markFormClean();
  }

  void _syncOpenRecordFromLiveData() {
    if (_editingId == null || _hasUnsavedChanges) return;
    final liveRecord =
        _timeoffRecords.cast<Map<String, dynamic>?>().firstWhere(
              (record) => _timeOffRecordId(record) == _editingId,
              orElse: () => null,
            );
    if (liveRecord != null) {
      _applyEditingRecord(liveRecord, preserveCalendarMonth: true);
    }
  }

  void _applyEditingRecord(
    Map<String, dynamic> record, {
    bool preserveCalendarMonth = false,
  }) {
    _editingRecord = Map<String, dynamic>.from(record);
    _editingId = _timeOffRecordId(record);
    _timeOffType = _leaveTypeFromRecord(record);
    _selectedDates = TimeOffService.selectedDatesForRecord(record)
        .map(_dateOnly)
        .toSet();
    _deselectedDates.clear();
    _notesController.text = (record['notes'] ?? '').toString();

    if (_selectedDates.isEmpty) {
      _startDate = DateTime.now();
      _endDate = DateTime.now();
    } else {
      _syncSelectionBounds();
    }

    if (!preserveCalendarMonth) {
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
      _calendarMonth2 =
          DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);

      // Same rule as _resetFormFields: keep the record's own month when it
      // has dates; only clamp to the current month when starting fresh.
      if (_selectedDates.isEmpty) {
        final now = DateTime.now();
        final currentMonth = DateTime(now.year, now.month, 1);
        if (_calendarMonth.isBefore(currentMonth)) {
          _calendarMonth = currentMonth;
          _calendarMonth2 = DateTime(currentMonth.year, currentMonth.month + 1, 1);
        }
      }
    }

    _invalidateDateTypeMap();
    _markFormClean();
  }

  Future<void> _switchToLeaveType(String type) async {
    final normalizedType = TimeOffService.normalizeLeaveType(type);
    if (normalizedType == _timeOffType) return;

    if (_isAggregateOverview) {
      setState(() {
        _timeOffType = normalizedType;
        _syncAggregateDatesForType();
      });
      return;
    }

    _stashCurrentDraft();

    setState(() {
      _timeOffType = normalizedType;
      _hasTypeChanged = true;
      _editingRecord = null;
      _editingId = null;
      _deselectedDates.clear();

      final draft = _pendingDrafts[_draftKeyFor(null, normalizedType)];
      if (draft != null) {
        _selectedDates = Set<DateTime>.from(draft.selectedDates);
        _notesController.text = draft.notes;
        _hasDateSelectionChanged = true;
        _syncSelectionBounds();
      } else {
        _selectedDates.clear();
        _notesController.clear();
        _startDate = DateTime.now();
        _endDate = DateTime.now();
        _hasDateSelectionChanged = false;
      }
      _invalidateDateTypeMap();
    });
  }

  Future<bool> _confirmDiscardChanges() async {
    if (_bypassingConfirm || !_hasUnsavedChanges || !mounted) {
      return !_hasUnsavedChanges || _bypassingConfirm;
    }

    final shouldDiscard = await _showDiscardDialog();
    if (shouldDiscard == true) _bypassingConfirm = true;
    return shouldDiscard ?? false;
  }

  Future<bool?> _showDiscardDialog() => UnsavedChangesDialog.show(context);

  Future<void> _toggleDate(DateTime date) async {
    final selectedDate = _dateOnly(date);
    final existingType = _selectedDateToTypeMap[selectedDate];
    final isRemoving = existingType != null;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    if (selectedDate.isBefore(todayStart)) {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'past_time_off_edit_blocked'.tr(), isError: true);
      }
      return;
    }

    if (isRemoving) {
      setState(() {
        _selectedDates.remove(selectedDate);
        _deselectedDates.add(selectedDate);
        for (final draft in _pendingDrafts.values) {
          draft.selectedDates.remove(selectedDate);
        }
        _pendingDrafts
            .removeWhere((_, draft) => draft.selectedDates.isEmpty);
        _hasDateSelectionChanged = true;
        _invalidateDateTypeMap();
        _syncSelectionBounds();
      });
      return;
    }

    if (_isAggregateOverview) {
      _handleAggregateToggle(selectedDate);
      return;
    }

    if (_isNonWorkingDate(selectedDate)) {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'time_off_non_working_day_blocked'.tr(), isError: true);
      }
      return;
    }

    if (_selectedWorker != null) {
      final existingLeave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: selectedDate,
        excludingRecordId: _editingId,
      );

      if (existingLeave != null) {
        final existingType = TimeOffService.normalizeLeaveType(
            (existingLeave['action'] ?? existingLeave['type']).toString());
        final currentType = TimeOffService.normalizeLeaveType(_timeOffType);
        if (existingType != currentType) {
          return;
        }
        if (_editingId == null || _editingId == _timeOffRecordId(existingLeave)) {
          setState(() {
            _deselectedDates.add(selectedDate);
            _hasDateSelectionChanged = true;
            _invalidateDateTypeMap();
            _syncSelectionBounds();
          });
          return;
        }
        if (!mounted) return;
        _stashCurrentDraft();
        setState(() {
          _applyEditingRecord(existingLeave, preserveCalendarMonth: true);
          _selectedDates.remove(selectedDate);
          _deselectedDates.add(selectedDate);
          _hasDateSelectionChanged = true;
          _invalidateDateTypeMap();
          _syncSelectionBounds();
        });
        return;
      }
    }

    if (_usesPaidAllowance && _availableDays <= 0) {
      if (mounted) {
        FlashySnackBar.show(context,
            message: _insufficientBalanceMessage, isError: true);
      }
      return;
    }

    setState(() {
      _selectedDates.add(selectedDate);
      _deselectedDates.remove(selectedDate);
      _hasDateSelectionChanged = true;
      _invalidateDateTypeMap();
      _syncSelectionBounds();
    });
  }

  void _handleAggregateToggle(DateTime selectedDate) {
    final owningRecord = TimeOffService.activeLeaveForWorker(
      _selectedWorkerForService,
      _timeoffRecords,
      onDate: selectedDate,
    );

    if (owningRecord == null ||
        !TimeOffService.recordHasLeaveType(owningRecord, _timeOffType)) {
      return;
    }
    if (!mounted) return;

    setState(() {
      _isAggregateOverview = false;
      _applyEditingRecord(owningRecord, preserveCalendarMonth: true);
      _selectedDates.remove(selectedDate);
      _deselectedDates.add(selectedDate);
      _hasDateSelectionChanged = true;
      _invalidateDateTypeMap();
      _syncSelectionBounds();
    });
  }

  void _finishDateDrag() {
    if (_dragExceededAvailableDays && mounted) {
      FlashySnackBar.show(context,
          message: _insufficientBalanceMessage, isError: true);
    }

    _dragAnchorDate = null;
    _lastDragDate = null;
    _selectionBeforeDrag = const <DateTime>{};
    _dragExceededAvailableDays = false;
    _dragStartPosition = null;
    _dragMoved = false;
  }

  DateTime? _dateAtGridPosition(DateTime monthDate, Offset position) {
    final adjustedDy = position.dy - _headerHeight;
    final adjustedDx = position.dx - _calendarPadding;
    if (adjustedDy < 0 || adjustedDx < 0) return null;

    final column = (adjustedDx / _cellExtent).floor();
    final row = (adjustedDy / _cellExtent).floor();
    if (column < 0 || column > 6 || row < 0 || row > 5) return null;

    final firstWeekday =
        DateTime(monthDate.year, monthDate.month, 1).weekday;
    final startIndex = firstWeekday == 7 ? 0 : firstWeekday;
    final day = (row * 7) + column - startIndex + 1;
    final daysInMonth =
        DateTime(monthDate.year, monthDate.month + 1, 0).day;
    if (day < 1 || day > daysInMonth) return null;

    return DateTime(monthDate.year, monthDate.month, day);
  }

  Future<void> _handleSave() async {
    if (widget.viewOnly || _isLoading || !_hasUnsavedChanges) return;

    _stashCurrentDraft();

    if (_pendingDrafts.isNotEmpty) {
      await _savePendingDrafts();
      return;
    }

    if (!_validateSavePreConditions()) return;

    if (_selectedDates.isEmpty && _editingId != null) {
      await _handleCancelTimeOff();
      return;
    }

    if (!_validateSaveDates()) return;

    setState(() => _isLoading = true);

    try {
      final workerId = _resolveWorkerId();
      if (workerId.isEmpty) throw StateError('Missing worker id');

      if (_editingRecord != null &&
          !TimeOffService.recordHasLeaveType(
              _editingRecord!, _timeOffType)) {
        throw StateError(
            'The selected leave type does not match the record being edited');
      }

      final recordMap = _buildTimeOffRecord(workerId);

      if (_isGuest) {
        _saveGuestTimeOff(recordMap, workerId);
      } else {
        await _firestore.saveTimeOffWithWorkerBalance(
          timeOffId: _editingId,
          record: recordMap,
          workerId: workerId,
          leaveType: _timeOffType,
          requestedDays: _requestedDays,
        );
      }

      final wasEditing = _editingId != null;
      if (!mounted) return;

      setState(() {
        _editingRecord = null;
        _editingId = null;
        _selectedDates.clear();
        _startDate = DateTime.now();
        _endDate = DateTime.now();
        _notesController.clear();
        _timeOffType = 'Annual Leave';
        _invalidateDateTypeMap();
        _markFormClean();
      });

      await _loadTimeoffForSelectedWorker();
      if (!mounted) return;

      FlashySnackBar.show(
        context,
        message: (wasEditing
                ? 'update_time_off_success'
                : 'assign_time_off_success')
            .tr(
          namedArgs: {
            'name': (_selectedWorker?['name'] ?? 'Worker').toString(),
          },
        ),
      );
      widget.onBack();
    } on DuplicateTimeOffDateException {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'time_off_dates_overlap'.tr(), isError: true);
      }
    } on PastTimeOffEditException {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'past_time_off_edit_blocked'.tr(), isError: true);
      }
    } on ValidationException catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.message, isError: true);
      }
    } on StateError catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'assign_time_off_failed'.tr(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validateSavePreConditions() {
    if (_editingRecord != null) {
      final oldDates =
          TimeOffService.selectedDatesForRecord(_editingRecord!);
      if (TimeOffService.hasPastDateModification(
          oldDates: oldDates, newDates: _selectedDates)) {
        FlashySnackBar.show(context,
            message: 'past_time_off_edit_blocked'.tr(), isError: true);
        return false;
      }
    }

    if (_editingRecord == null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (_selectedDates.any((d) => d.isBefore(today))) {
        FlashySnackBar.show(context,
            message: 'past_time_off_edit_blocked'.tr(), isError: true);
        return false;
      }
    }

    if (_selectedWorker == null && _selectedDates.isEmpty) {
      FlashySnackBar.show(context,
          message: 'please_fill_all_fields'.tr(), isError: true);
      return false;
    }

    if (_selectedWorker == null) {
      FlashySnackBar.show(context,
          message: 'please_select_worker_first'.tr(), isError: true);
      return false;
    }

    if (!_isEligibleWorker(_selectedWorker!)) {
      FlashySnackBar.show(context,
          message: 'guest_action_not_allowed'.tr(), isError: true);
      return false;
    }

    return true;
  }

  bool _validateSaveDates() {
    if (_selectedDates.isEmpty) {
      FlashySnackBar.show(context,
          message: 'please_select_dates'.tr(), isError: true);
      return false;
    }

    if (_selectedDates.any(_isNonWorkingDate)) {
      FlashySnackBar.show(context,
          message: 'time_off_non_working_day_blocked'.tr(), isError: true);
      return false;
    }

    final joiningDate = AppDateUtils.dateFromValue(
      _selectedWorker?['joiningDate'] ??
          _selectedWorker?['dateOfJoining'],
    );
    if (joiningDate != null) {
      final normJoining =
          DateTime(joiningDate.year, joiningDate.month, joiningDate.day);
      if (_selectedDates.any((d) =>
          DateTime(d.year, d.month, d.day).isBefore(normJoining))) {
        FlashySnackBar.show(
          context,
          message: 'Cannot assign leave before worker joining date.',
          isError: true,
        );
        return false;
      }
    }

    if (TimeOffService.hasOverlappingApprovedLeave(
      _isGuest ? _selectedWorker! : _selectedWorkerForService,
      _timeoffRecords,
      _selectedDates,
      excludingRecordId: _editingId,
    )) {
      FlashySnackBar.show(context,
          message: 'time_off_dates_overlap'.tr(), isError: true);
      return false;
    }

    if (_requestedDaysExceedAvailable) {
      FlashySnackBar.show(context,
          message: _insufficientBalanceMessage, isError: true);
      return false;
    }

    return true;
  }

  String _resolveWorkerId() {
    final workerIdentity =
        _selectedWorker!['workerId'] ?? _selectedWorker!['id'] ?? '';
    return workerIdentity.toString().trim();
  }

  Map<String, dynamic> _buildTimeOffRecord(String workerId) {
    final worker = _selectedWorker!;
    final workerName = (worker['name'] ?? 'Worker').toString();
    return {
      'workerId': _isGuest
          ? (worker['workerId'] ?? worker['id'] ?? '')
          : workerId,
      'name': workerName,
      'email': worker['email'] ?? '',
      'position': worker['position'] ?? 'Worker',
      'contact': _getWorkerPhone(worker),
      'action': _timeOffType,
      'type': _timeOffType,
      'startDate': _dateOnlyString(_startDate),
      'endDate': _dateOnlyString(_endDate),
      'selectedDates': _sortedSelectedDates.map(_dateOnlyString).toList(),
      'notes': _notesController.text.trim(),
      'requestedDays': _requestedDays,
      'status': 'Approved',
      'isPaidLeave': _isPaidLeave,
      'workerName': workerName,
      'workerAvatar': worker['profileImage'] ?? '',
    };
  }

  void _saveGuestTimeOff(
      Map<String, dynamic> recordMap, String workerId) {
    Map<String, dynamic>? previousGuestRecord;

    if (_editingId != null) {
      final idx =
          DummyData.timeoff.indexWhere((t) => t['id'] == _editingId);
      if (idx != -1) {
        previousGuestRecord =
            Map<String, dynamic>.from(DummyData.timeoff[idx]);
        DummyData.timeoff[idx] = {
          ...DummyData.timeoff[idx],
          ...recordMap,
        };
      }
    } else {
      DummyData.timeoff.insert(0, {
        ...recordMap,
        'id': 'guest_to_${DateTime.now().millisecondsSinceEpoch}',
      });
    }

    _updateGuestWorkerBalance(workerId, previousGuestRecord);
    DummyData.saveToPrefs();
  }

  void _updateGuestWorkerBalance(
      String workerId, Map<String, dynamic>? previousRecord) {
    final leaveField = _leaveFieldForType(_timeOffType);

    final workerEmail =
        (_selectedWorker!['email'] ?? '').toString().trim().toLowerCase();
    final workerIdx = DummyData.workers.indexWhere((w) =>
        (w['email'] ?? '').toString().trim().toLowerCase() == workerEmail);

    if (workerIdx == -1) return;

    final worker = DummyData.workers[workerIdx];
    final currentMap = Map<String, dynamic>.from(
      worker['leaveBalances'] as Map? ??
          _buildDefaultLeaveBalances(worker),
    );

    if (previousRecord != null) {
      final oldField = _leaveFieldForType(
          TimeOffService.leaveType(previousRecord));
      final oldDays =
          TimeOffService.selectedDatesForRecord(previousRecord).length;
      if (oldField.isNotEmpty && oldDays > 0) {
        final oldBalance =
            int.tryParse(currentMap[oldField]?.toString() ?? '0') ?? 0;
        currentMap[oldField] = oldBalance + oldDays;
      }
    }

    final currentVal =
        int.tryParse(currentMap[leaveField]?.toString() ?? '0') ?? 0;
    currentMap[leaveField] = (currentVal - _requestedDays).clamp(0, 999);

    DummyData.workers[workerIdx].addAll(
      TimeOffService.canonicalWorkerLeaveFields(worker,
          remainingBalances: currentMap),
    );
  }

  Map<String, dynamic> _buildDefaultLeaveBalances(
      Map<String, dynamic> worker) {
    int parse(String key) =>
        int.tryParse((worker[key] ?? '0').toString()) ?? 0;

    return {
      'annualLeave':
          parse('availableAnnualLeaves').clamp(0, 999) > 0
              ? parse('availableAnnualLeaves')
              : parse('annualLeaves'),
      'sickLeave': parse('availableSickLeaves').clamp(0, 999) > 0
          ? parse('availableSickLeaves')
          : parse('sickLeaves'),
      'casualLeave':
          parse('availableCasualLeaves').clamp(0, 999) > 0
              ? parse('availableCasualLeaves')
              : parse('casualLeaves'),
      'medicalLeave':
          parse('availableMedicalLeaves').clamp(0, 999) > 0
              ? parse('availableMedicalLeaves')
              : parse('medicalLeaves'),
    };
  }

  String _leaveFieldForType(String type) {
    return switch (TimeOffService.normalizeLeaveType(type)) {
      'Annual Leave' => 'annualLeave',
      'Sick Leave' => 'sickLeave',
      'Casual Leave' => 'casualLeave',
      'Medical Leave' => 'medicalLeave',
      _ => '',
    };
  }

  Future<void> _handleCancelTimeOff() async {
    setState(() => _isLoading = true);
    try {
      final workerId = _resolveWorkerId();
      if (workerId.isEmpty) throw StateError('Missing worker id');

      if (_isGuest) {
        _cancelGuestTimeOff(workerId);
      } else {
        await _firestore.cancelTimeOffWithWorkerBalance(
          timeOffId: _editingId!,
          workerId: workerId,
          fallbackRecord: _editingRecord,
        );
      }

      if (!mounted) return;
      await _loadTimeoffForSelectedWorker();
      if (!mounted) return;

      setState(_markFormClean);
      FlashySnackBar.show(
        context,
        message: 'update_time_off_success'.tr(
          namedArgs: {
            'name': (_selectedWorker?['name'] ?? 'Worker').toString(),
          },
        ),
      );
      widget.onBack();
    } on PastTimeOffEditException {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'past_time_off_edit_blocked'.tr(), isError: true);
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'assign_time_off_failed'.tr(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _cancelGuestTimeOff(String workerId) {
    final recordIndex = DummyData.timeoff
        .indexWhere((r) => r['id']?.toString() == _editingId);
    if (recordIndex == -1) {
      throw StateError('Time off record does not exist');
    }

    final oldRecord = DummyData.timeoff[recordIndex];
    final workerIndex = DummyData.workers.indexWhere(
      (w) =>
          (w['workerId'] ?? w['id'] ?? '').toString().trim() == workerId,
    );

    if (workerIndex != -1) {
      final balances = Map<String, dynamic>.from(
        TimeOffService.canonicalWorkerLeaveFields(
                DummyData.workers[workerIndex])['leaveBalances']
            as Map,
      );
      final oldField =
          _leaveFieldForType(TimeOffService.leaveType(oldRecord));
      if (oldField.isNotEmpty) {
        final current =
            int.tryParse(balances[oldField]?.toString() ?? '0') ?? 0;
        balances[oldField] = current +
            TimeOffService.selectedDatesForRecord(oldRecord).length;
        DummyData.workers[workerIndex].addAll(
          TimeOffService.canonicalWorkerLeaveFields(
            DummyData.workers[workerIndex],
            remainingBalances: balances,
          ),
        );
      }
    }

    final oldDates = TimeOffService.selectedDatesForRecord(oldRecord);
    final oldDatesFormatted = oldDates.map(_dateOnlyString).toList();
    final cleanRecord = Map<String, dynamic>.from(oldRecord)
      ..remove('selectedDates')
      ..remove('startDate')
      ..remove('endDate');

    DummyData.timeoff[recordIndex] = {
      ...cleanRecord,
      'status': 'Cancelled',
      if (oldDatesFormatted.isNotEmpty)
        'originalSelectedDates': oldDatesFormatted,
    };

    DummyData.saveToPrefs();
  }

  Future<void> _savePendingDrafts() async {
    final worker = _selectedWorker;
    if (worker == null) {
      FlashySnackBar.show(context,
          message: 'please_select_worker_first'.tr(), isError: true);
      return;
    }
    if (!_isEligibleWorker(worker)) {
      FlashySnackBar.show(context,
          message: 'guest_action_not_allowed'.tr(), isError: true);
      return;
    }

    final workerId = _resolveWorkerId();
    if (workerId.isEmpty) {
      FlashySnackBar.show(context,
          message: 'assign_time_off_failed'.tr(), isError: true);
      return;
    }

    final drafts =
        _pendingDrafts.values.where((d) => d.hasChanges).toList();

    if (!_validatePendingDrafts(drafts)) return;

    setState(() => _isLoading = true);
    try {
      final batchItems = await _buildBatchItems(drafts, workerId);

      if (batchItems.isNotEmpty) {
        if (_isGuest) {
          for (final item in batchItems) {
            DummyData.timeoff.add({
              ...item['record'] as Map<String, dynamic>,
              'id':
                  'guest_${DateTime.now().millisecondsSinceEpoch}_${DummyData.timeoff.length}',
            });
          }
          await DummyData.saveToPrefs();
        } else {
          await _firestore.saveMultipleTimeOffWithWorkerBalance(
            workerId: workerId,
            items: batchItems,
          );
        }
      }

      if (!mounted) return;
      _pendingDrafts.clear();
      _invalidateDateTypeMap();
      _markFormClean();
      FlashySnackBar.show(
        context,
        message: 'assign_time_off_success'.tr(
          namedArgs: {
            'name': (worker['name'] ?? 'Worker').toString(),
          },
        ),
      );
      widget.onBack();
    } on DuplicateTimeOffDateException {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'time_off_dates_overlap'.tr(), isError: true);
      }
    } on PastTimeOffEditException {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'past_time_off_edit_blocked'.tr(), isError: true);
      }
    } on ValidationException catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.message, isError: true);
      }
    } on StateError catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(context,
            message: 'assign_time_off_failed'.tr(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validatePendingDrafts(List<PendingTimeOffDraft> drafts) {
    final pendingDates = <DateTime>{};

    for (final draft in drafts) {
      if (draft.selectedDates.any(_isNonWorkingDate)) {
        FlashySnackBar.show(context,
            message: 'time_off_non_working_day_blocked'.tr(),
            isError: true);
        return false;
      }
      for (final date in draft.selectedDates) {
        if (!pendingDates.add(_dateOnly(date))) {
          FlashySnackBar.show(context,
              message: 'time_off_dates_overlap'.tr(), isError: true);
          return false;
        }
      }
      if (TimeOffService.hasOverlappingApprovedLeave(
        _selectedWorkerForService,
        _timeoffRecords,
        draft.selectedDates,
        excludingRecordId: draft.editingId,
      )) {
        FlashySnackBar.show(context,
            message: 'time_off_dates_overlap'.tr(), isError: true);
        return false;
      }

      final available = TimeOffService.availableBalanceForEditingRecord(
        _selectedWorkerForService,
        _timeoffRecords,
        draft.leaveType,
        draft.editingRecord,
      );
      if (_paidLeaveTypes.contains(draft.leaveType) &&
          draft.selectedDates.length > available) {
        FlashySnackBar.show(
          context,
          message: 'only_leave_days_available'.tr(namedArgs: {
            'count': '$available',
            'type':
                LocalizationHelper.localizeLeaveType(draft.leaveType),
          }),
          isError: true,
        );
        return false;
      }
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> _buildBatchItems(
    List<PendingTimeOffDraft> drafts,
    String workerId,
  ) async {
    final worker = _selectedWorker!;
    final batchItems = <Map<String, dynamic>>[];
    final workerName = (worker['name'] ?? 'Worker').toString();

    for (final draft in drafts) {
      if (draft.selectedDates.isEmpty && draft.editingId != null) {
        await _firestore.cancelTimeOffWithWorkerBalance(
          timeOffId: draft.editingId!,
          workerId: workerId,
          fallbackRecord: draft.editingRecord,
        );
        continue;
      }
      if (draft.selectedDates.isEmpty) continue;

      final sortedDates = draft.selectedDates.toList()..sort();
      batchItems.add({
        'timeOffId': draft.editingId,
        'record': {
          'workerId': workerId,
          'name': workerName,
          'email': worker['email'] ?? '',
          'position': worker['position'] ?? 'Worker',
          'contact': _getWorkerPhone(worker),
          'action': draft.leaveType,
          'type': draft.leaveType,
          'startDate': _dateOnlyString(sortedDates.first),
          'endDate': _dateOnlyString(sortedDates.last),
          'selectedDates':
              sortedDates.map(_dateOnlyString).toList(),
          'notes': draft.notes,
          'requestedDays': sortedDates.length,
          'status': 'Approved',
          'isPaidLeave':
              _paidLeaveTypes.contains(draft.leaveType),
          'workerName': workerName,
          'workerAvatar': worker['profileImage'] ?? '',
        },
        'leaveType': draft.leaveType,
        'requestedDays': sortedDates.length,
      });
    }

    return batchItems;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _confirmDiscardChanges();
        if (shouldLeave && mounted && context.mounted) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(),
                    const SizedBox(height: 24),
                    _buildMainCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'assign_time_off'.tr(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const Spacer(),
        for (int i = 0; i < _legendTypes.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          _buildLeaveLegendItem(_legendTypes[i], _legendColors[i]),
        ],
      ],
    );
  }

  Widget _buildLeaveLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(4)),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.only(
          left: 32, right: 32, top: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final shouldLeave = await _confirmDiscardChanges();
              if (shouldLeave) widget.onBack();
            },
            child: const Padding(
              padding: EdgeInsets.only(top: 2.0),
              child: Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF000000), size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'workforce'.tr(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF000000),
              fontFamily: 'SF Pro Display',
            ),
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 24),
          GestureDetector(
              onTap: widget.onProfileTap,
              child: const UserAvatar()),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    if (_selectedWorker == null) return _buildNoWorkerSelected();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopForm(),
          const SizedBox(height: 32),
          IgnorePointer(
              ignoring: widget.viewOnly,
              child: _buildUnifiedDaysGrid()),
          const SizedBox(height: 8),
          _buildCalendarHintRow(),
          const SizedBox(height: 4),
          _buildNotesAndSummary(),
        ],
      ),
    );
  }

  Widget _buildCalendarHintRow() {
    return Row(
      children: [
        const Icon(Icons.touch_app_outlined,
            size: 18, color: Color(0xFF64748B)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            (widget.viewOnly ? 'selected_dates' : 'tap_dates_to_select')
                .tr(),
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontFamily: 'SF Pro Display'),
          ),
        ),
        if (_selectedDates.isNotEmpty &&
            !widget.viewOnly &&
            !_isAggregateOverview)
          TextButton(
            onPressed: () {
              setState(() {
                _selectedDates.clear();
                _hasDateSelectionChanged = true;
                _invalidateDateTypeMap();
                _syncSelectionBounds();
              });
            },
            child: Text('clear_selection'.tr()),
          ),
      ],
    );
  }

  Widget _buildNoWorkerSelected() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const Icon(Icons.person_off_rounded,
                size: 64, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 24),
          Text(
            'no_worker_selected'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
              fontFamily: 'SF Pro Display',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'select_worker_to_assign'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontFamily: 'SF Pro Display'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopForm() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
            flex: 3,
            child: _buildLabeledDropdown(
                'time_off_type'.tr(), _timeOffType)),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'selected_dates'.tr(),
            _currentSelectedDatesSummary,
            onTap: _sortedSelectedDates.isEmpty
                ? null
                : () => _showSelectedDatesListDialog(context),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
            flex: 3,
            child: _buildLabeledInput(
                'selected_days'.tr(), '$_selectedDaysCount')),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0247C4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              onPressed: (widget.viewOnly ||
                      _selectedWorker == null ||
                      _isLoading ||
                      _isAggregateOverview ||
                      !_hasUnsavedChanges)
                  ? null
                  : () {
                      if (_isGuest) {
                        showGuestRestrictionDialog(context);
                        return;
                      }
                      _handleSave();
                    },
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      (_editingId == null ? 'assign' : 'save').tr(),
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabeledDropdown(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: Theme(
              data: ThemeData(canvasColor: Colors.white),
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                dropdownColor: Colors.white,
                icon: const Icon(Icons.arrow_drop_down,
                    color: Colors.black),
                style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    color: Colors.black),
                selectedItemBuilder: (_) =>
                    _leaveTypeOptions.map((opt) {
                  final lbl = opt['labelKey']!.tr();
                  final typeVal = opt['value']!;
                  final avail = _availableDaysForType(typeVal);
                  final displayLabel =
                      (_selectedWorker != null && avail < 999)
                          ? '$lbl ($avail)'
                          : lbl;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      displayLabel,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: LeaveColors.getTextColor(typeVal),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                items: _leaveTypeOptions.map((opt) {
                  final lbl = opt['labelKey']!.tr();
                  final typeVal = opt['value']!;
                  final avail = _availableDaysForType(typeVal);
                  final displayLabel =
                      (_selectedWorker != null && avail < 999)
                          ? '$lbl ($avail)'
                          : lbl;
                  return DropdownMenuItem<String>(
                    value: typeVal,
                    child: Text(
                      displayLabel,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: LeaveColors.getTextColor(typeVal),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v == null || v == _timeOffType) return;
                  if (widget.viewOnly) {
                    setState(() {
                      _timeOffType = v;
                      _invalidateDateTypeMap();
                      _syncViewOnlyDatesForType();
                    });
                    return;
                  }
                  unawaited(_switchToLeaveType(v));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabeledInput(String label, String value,
      {VoidCallback? onTap}) {
    Widget content = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontFamily: 'SF Pro Display'),
      ),
    );

    if (onTap != null) {
      content = GestureDetector(onTap: onTap, child: content);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget _buildCalendar(DateTime monthDate,
      {required bool isStartCalendar}) {
    final monthYear =
        '${_getMonthName(monthDate.month)} ${monthDate.year}'
            .toUpperCase();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: _calendarContentWidth),
        child: Column(
          children: [
            _buildCalendarNav(monthYear, isStartCalendar),
            const SizedBox(height: 16),
            _buildWeekdayRow(),
            const SizedBox(height: 8),
            _buildDaysGrid(monthDate),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarNav(String monthYear, bool isStartCalendar) {
    void navigateMonth(int delta) {
      final ref =
          isStartCalendar ? _calendarMonth : _calendarMonth2;
      final newMonth =
          DateTime(ref.year, ref.month + delta, 1);
      if (newMonth.year != DateTime.now().year) return;
      setState(() {
        if (isStartCalendar) {
          _calendarMonth = newMonth;
        } else {
          _calendarMonth2 = newMonth;
        }
      });
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () => navigateMonth(-1),
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.chevron_left,
                size: 20, color: Colors.black),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          monthYear,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFamily: 'SF Pro Display'),
        ),
        const SizedBox(width: 16),
        InkWell(
          onTap: () => navigateMonth(1),
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.chevron_right,
                size: 20, color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _weekdayKeys.length; i++) ...[
          _buildWeekday(_weekdayKeys[i].tr()),
          if (i < 6) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildWeekday(String day) {
    final shortDay = day.length > 3 ? day.substring(0, 3) : day;

    return Container(
      width: 50,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0247C4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shortDay.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildUnifiedDaysGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridScale = constraints.maxWidth < _naturalRowWidth
            ? constraints.maxWidth / _naturalRowWidth
            : 1.0;

        Offset toGridSpace(Offset pos) => gridScale == 1.0
            ? pos
            : Offset(pos.dx / gridScale, pos.dy / gridScale);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanDown: (details) {
            final pos = toGridSpace(details.localPosition);
            final isSecond = pos.dx > _containerWidth + 24;
            final monthDate =
                isSecond ? _calendarMonth2 : _calendarMonth;
            final adjustedPos = isSecond
                ? Offset(pos.dx - _containerWidth - 24, pos.dy)
                : pos;
            _dragAnchorDate =
                _dateAtGridPosition(monthDate, adjustedPos);
            _lastDragDate = null;
            _selectionBeforeDrag =
                Set<DateTime>.from(_selectedDates);
            _dragExceededAvailableDays = false;
            _dragStartPosition = pos;
            _dragMoved = false;
          },
          onPanUpdate: (details) {
            final pos = toGridSpace(details.localPosition);
            if (_dragStartPosition != null && !_dragMoved) {
              final dx =
                  (pos.dx - _dragStartPosition!.dx).abs();
              final dy =
                  (pos.dy - _dragStartPosition!.dy).abs();
              if (dx > 18 || dy > 18) _dragMoved = true;
            }
            if (!_dragMoved) return;

            final anchor = _dragAnchorDate;
            final isSecond = pos.dx > _containerWidth + 24;
            final monthDate =
                isSecond ? _calendarMonth2 : _calendarMonth;
            final adjustedPos = isSecond
                ? Offset(pos.dx - _containerWidth - 24, pos.dy)
                : pos;
            final current =
                _dateAtGridPosition(monthDate, adjustedPos);
            if (anchor == null ||
                current == null ||
                current == _lastDragDate) return;
            _lastDragDate = current;

            final candidate =
                Set<DateTime>.from(_selectionBeforeDrag);
            final isDragRemoving =
                _selectionBeforeDrag.contains(_dragAnchorDate);
            var exceededAvailable = false;
            final today = DateTime.now();
            final todayDate =
                DateTime(today.year, today.month, today.day);

            for (final date in TimeOffService.inclusiveDateRange(
                anchor, current)) {
              if (_isNonWorkingDate(date)) continue;
              if (isDragRemoving) {
                if (date.isBefore(todayDate)) continue;
                candidate.remove(date);
              } else {
                if (candidate.contains(date)) continue;
                if (_selectedWorker != null) {
                  final savedLeave =
                      TimeOffService.activeLeaveForWorker(
                    _selectedWorker!,
                    _timeoffRecords,
                    onDate: date,
                    excludingRecordId: _editingId,
                  );
                  if (savedLeave != null) continue;
                }
                if (_usesPaidAllowance &&
                    candidate.length >= _baseAvailableDays) {
                  if (!_isGuest) exceededAvailable = true;
                  break;
                }
                candidate.add(date);
              }
            }

            setState(() {
              _selectedDates = candidate;
              _hasDateSelectionChanged = true;
              _dragExceededAvailableDays = exceededAvailable;
              _invalidateDateTypeMap();
              _syncSelectionBounds();
            });
          },
          onPanEnd: (_) {
            if (!_dragMoved && _dragAnchorDate != null) {
              unawaited(_toggleDate(_dragAnchorDate!));
            }
            _finishDateDrag();
          },
          onPanCancel: _finishDateDrag,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCalendar(_calendarMonth,
                    isStartCalendar: true),
                const SizedBox(width: 24),
                _buildCalendar(_calendarMonth2,
                    isStartCalendar: false),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDaysGrid(DateTime monthDate) {
    final daysInMonth =
        DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final firstWeekday =
        DateTime(monthDate.year, monthDate.month, 1).weekday;
    final startIndex = firstWeekday == 7 ? 0 : firstWeekday;

    final rows = <Widget>[];
    int currentDay = 1;

    for (int i = 0; i < 6; i++) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < 7; j++) {
        if (i == 0 && j < startIndex) {
          rowChildren.add(const SizedBox(width: 50, height: 50));
        } else if (currentDay <= daysInMonth) {
          final cellDate = DateTime(
              monthDate.year, monthDate.month, currentDay);
          rowChildren.add(_buildDayCell(
            '$currentDay',
            isSelected: _selectedDates.contains(cellDate),
            date: cellDate,
            isDisabled: _isNonWorkingDate(cellDate),
          ));
          currentDay++;
        } else {
          rowChildren.add(const SizedBox(width: 50, height: 50));
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 4));
      }
      rows.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: rowChildren));
      if (currentDay > daysInMonth && i >= 5) break;
      if (i < 5) rows.add(const SizedBox(height: 4));
    }

    return Column(children: rows);
  }

  Widget _buildDayCell(
    String day, {
    bool isSelected = false,
    DateTime? date,
    bool isDisabled = false,
  }) {
    if (day.isEmpty) {
      return const SizedBox(width: 50, height: 50);
    }

    final cellDate = date != null ? _dateOnly(date) : null;
    final dateTypeMap = _selectedDateToTypeMap;
    final activeSessionType =
        cellDate != null ? dateTypeMap[cellDate] : null;
    final isSelectedInSession = activeSessionType != null;

    Map<String, dynamic>? savedLeave;
    if (!isSelectedInSession &&
        !_deselectedDates.contains(cellDate) &&
        date != null &&
        _selectedWorker != null) {
      savedLeave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: date,
        excludingRecordId: _editingId,
      );
    }

    final savedType = savedLeave != null
        ? (savedLeave['action'] ?? savedLeave['type']).toString()
        : null;
    final isCellHighlighted =
        isSelectedInSession || savedLeave != null;
    final effectiveType =
        isSelectedInSession ? activeSessionType : savedType;
    final effectiveColor = effectiveType != null
        ? LeaveColors.getColor(effectiveType)
        : null;

    final bgColor = isCellHighlighted
        ? effectiveColor!
        : (isDisabled
            ? const Color(0xFFF1F5F9)
            : Colors.transparent);
    final borderColor = isCellHighlighted
        ? effectiveColor!
        : Colors.grey.shade300;
    final textColor = isDisabled && !isCellHighlighted
        ? const Color(0xFFB0B7C3)
        : (isCellHighlighted
            ? const Color(0xFFFFFFFF)
            : Colors.black);

    final tooltipType = effectiveType ?? _timeOffType;
    final tooltipOption = _leaveTypeOptions
        .cast<Map<String, String>?>()
        .firstWhere(
          (opt) => opt?['value'] == tooltipType,
          orElse: () => null,
        );
    final tooltipTypeLabel =
        tooltipOption?['labelKey']?.tr() ?? tooltipType;
    final tooltipDate = date == null ? '' : _formatDate(date);
    final tooltipColor = LeaveColors.getColor(tooltipType);

    return Center(
      child: Tooltip(
        message: '$tooltipTypeLabel\n$tooltipDate',
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tooltipColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
                color: tooltipColor.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'SF Pro Display',
          height: 1.35,
        ),
        textAlign: TextAlign.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: date == null
              ? null
              : () {
                  if (!_dragMoved) unawaited(_toggleDate(date));
                },
          child: SizedBox(
            width: 50,
            height: 50,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                day,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotesAndSummary() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 70, child: _buildNotesSection()),
        const SizedBox(width: 24),
        Expanded(
          flex: 30,
          child: Padding(
            padding: const EdgeInsets.only(top: 32),
            child: _buildSummarySection(),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'notes_label'.tr(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 130,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
          child: TextField(
            controller: _notesController,
            readOnly: widget.viewOnly || _isAggregateOverview,
            onChanged: (_) =>
                setState(() => _hasNotesChanged = true),
            maxLines: null,
            style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontFamily: 'SF Pro Display'),
            decoration: InputDecoration.collapsed(
              hintText: 'please_enter_notes'.tr(),
              hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummarySection() {
    return Column(
      children: [
        _buildSummaryRow(
          _availableLeaveLabel,
          '$_displayedLeaveBalance',
          _displayedLeaveBalance > 0 ? Colors.black : Colors.red,
        ),
        _buildSummaryRow(
            'requested_days'.tr(),
            '$_summaryRequestedDays',
            Colors.black),
        _buildSummaryRow(
          'remaining_days'.tr(),
          '$_remainingDaysAfterRequest',
          _remainingDaysAfterRequest >= 0
              ? Colors.black
              : Colors.red,
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
      String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display'),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  void _showSelectedDatesListDialog(BuildContext context) {
    final entries = _sortedSelectedDates
        .map(
            (d) => (d, TimeOffService.normalizeLeaveType(_timeOffType)))
        .toList();
    final localeName = context.locale.toString();

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (ctx) => Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                  color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Center(
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                width: 520,
                height: MediaQuery.sizeOf(ctx).height * 0.60,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(ctx).width * 0.90,
                  minHeight: 340,
                  maxHeight:
                      MediaQuery.sizeOf(ctx).height * 0.72,
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color:
                            Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDateDialogHeader(entries.length, ctx),
                    _buildDateDialogLegend(entries),
                    Flexible(
                        child: _buildDateDialogList(
                            entries, localeName)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDialogHeader(int count, BuildContext ctx) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: Color(0xFF004FDE)),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'selected_dates_count_title'
                  .tr(namedArgs: {'count': '$count'}),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.of(ctx).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDialogLegend(
      List<(DateTime, String)> entries) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: const Color(0xFFF8FAFC),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _legendTypes.map((type) {
          final color = LeaveColors.getColor(type);
          final count =
              entries.where((e) => e.$2 == type).length;
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LeaveColors.getBgColor(type),
              borderRadius: BorderRadius.circular(5),
              border:
                  Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Text(
              '${LocalizationHelper.localizeLeaveType(type)}: $count ${count == 1 ? 'day'.tr() : 'days'.tr()}',
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro Display'),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateDialogList(
      List<(DateTime, String)> entries, String localeName) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 40, horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle),
                child: const Icon(Icons.event_busy_rounded,
                    size: 32, color: Color(0xFF94A3B8)),
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
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(
          height: 1, color: Color(0xFFEEEEEE)),
      itemBuilder: (_, index) {
        final (date, type) = entries[index];
        final dayDisplayType =
            LocalizationHelper.localizeLeaveType(type);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
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
                    fontSize: 12,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  DateFormat.yMMMd(localeName).format(date),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              Text(
                DateFormat.EEEE(localeName).format(date),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              if (dayDisplayType.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: LeaveColors.getBgColor(type),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dayDisplayType,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: LeaveColors.getColor(type),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}