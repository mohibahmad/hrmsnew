import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/error_reporter.dart';
import '../services/preferences_service.dart';
import '../services/time_off_service.dart';
import '../utils/ui_utils.dart';
import '../utils/guest_restriction.dart';
import '../utils/date_time_utils.dart';
import '../utils/localization_helper.dart';

import 'package:easy_localization/easy_localization.dart';
import '../widgets/notification_bell.dart';

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
  ConsumerState<AssignTimeOffScreen> createState() =>
      _AssignTimeOffScreenState();
}

class LeaveColors {
  static const Color annual = Color(0xFFF59E0B);
  static const Color annualBg = Color(0xFFFFFBEB);

  static const Color sick = Color(0xFFEF4444);
  static const Color sickBg = Color(0xFFFEF2F2);

  static const Color casual = Color(0xFF3B82F6);
  static const Color casualBg = Color(0xFFEFF6FF);

  static const Color medical = Color(0xFF10B981);
  static const Color medicalBg = Color(0xFFECFDF5);

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
    if (lower.contains('annual')) return const Color(0xFFD97706);
    if (lower.contains('sick')) return const Color(0xFFDC2626);
    if (lower.contains('casual')) return const Color(0xFF1D4ED8);
    if (lower.contains('medical')) return const Color(0xFF047857);
    return const Color(0xFF1E293B);
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

class _AssignTimeOffScreenState extends ConsumerState<AssignTimeOffScreen> {
  static const List<Map<String, String>> _leaveTypeOptions = [
    {'value': 'Annual Leave', 'labelKey': 'annual_leave'},
    {'value': 'Sick Leave', 'labelKey': 'sick_leave_type'},
    {'value': 'Casual Leave', 'labelKey': 'casual_leave_type'},
    {'value': 'Medical Leave', 'labelKey': 'medical_leave_type'},
  ];

  static const List<String> _paidLeaveTypes = [
    'Annual Leave',
    'Sick Leave',
    'Casual Leave',
    'Medical Leave',
  ];

  static const double _calendarContentWidth = 7 * 50 + 6 * 4;

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

  bool _sameWorker(Map<String, dynamic> first, Map<String, dynamic> second) {
    String identityId(Map<String, dynamic> value) {
      final workerId = (value['workerId'] ?? '').toString().trim();
      return workerId.isNotEmpty
          ? workerId
          : (value['id'] ?? '').toString().trim();
    }

    final firstId = identityId(first);
    final secondId = identityId(second);
    if (firstId.isNotEmpty && secondId.isNotEmpty) return firstId == secondId;
    final firstEmail = (first['email'] ?? '').toString().trim().toLowerCase();
    final secondEmail = (second['email'] ?? '').toString().trim().toLowerCase();
    return firstEmail.isNotEmpty && firstEmail == secondEmail;
  }

  final TextEditingController _notesController = TextEditingController();
  String? _editingId;

  List<Map<String, dynamic>> _workers = [];
  Map<String, dynamic>? _selectedWorker;
  StreamSubscription? _workersSub;
  StreamSubscription? _timeoffSub;
  StreamSubscription? _attendanceSub;
  String _watchedTimeoffWorkerId = '';
  List<Map<String, dynamic>> _timeoffRecords = [];

  Map<String, dynamic>? _editingRecord;
  List<Map<String, dynamic>> _holidays = [];
  Set<int> _companyWorkingDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  StreamSubscription? _holidaysSub;
  bool _initialized = false;
  bool _hasTypeChanged = false;
  bool _hasDateSelectionChanged = false;
  bool _hasNotesChanged = false;
  bool _isAggregateOverview = false;
  final Map<String, PendingTimeOffDraft> _pendingDrafts = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialWorker != null) {
      _selectedWorker = widget.initialWorker;

      _isAggregateOverview =
          widget.initialWorker!['_aggregateTimeOffEdit'] == true;

      final hasAction = (widget.initialWorker!['action'] ?? '')
          .toString()
          .isNotEmpty;
      if (hasAction && !_isAggregateOverview) {
        _editingRecord = Map<String, dynamic>.from(widget.initialWorker!);
      }
    }
    _resetFormFields();
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

  bool _sameInitialSelection(
    Map<String, dynamic>? first,
    Map<String, dynamic>? second,
  ) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;

    final firstId = (first['id'] ?? '').toString().trim();
    final secondId = (second['id'] ?? '').toString().trim();
    final firstAction = (first['action'] ?? first['type'] ?? '')
        .toString()
        .trim();
    final secondAction = (second['action'] ?? second['type'] ?? '')
        .toString()
        .trim();

    return firstId == secondId &&
        firstAction == secondAction &&
        _sameWorker(first, second);
  }

  @override
  void didUpdateWidget(covariant AssignTimeOffScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final isGuest =
        _initialized && (_authService.currentUser?.isAnonymous ?? false);
    if (isGuest) {
      if (widget.initialWorker != null &&
          widget.initialWorker!['email'] != oldWidget.initialWorker?['email']) {
        _selectedWorker = widget.initialWorker;
        _resetFormFields();
        _loadTimeoffForSelectedWorker();
      }
      return;
    }

    if (!_sameInitialSelection(widget.initialWorker, oldWidget.initialWorker)) {
      _selectedWorker = widget.initialWorker;
      _resetFormFields();
      _loadTimeoffForSelectedWorker();
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _resetFormFields() {
    _pendingDrafts.clear();
    final source = _editingRecord ?? _selectedWorker;
    _hasTypeChanged = false;
    _hasDateSelectionChanged = false;
    _hasNotesChanged = false;
    if (_isAggregateOverview && source != null) {
      _editingRecord = null;
      _editingId = null;
      _timeOffType = 'Annual Leave';
      final aggregateDates = source['_aggregateDatesByType'];
      final datesForType = aggregateDates is Map
          ? aggregateDates[_timeOffType]
          : null;
      _selectedDates = datesForType is Iterable
          ? datesForType
                .map(TimeOffService.parseDate)
                .whereType<DateTime>()
                .toSet()
          : <DateTime>{};
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
      _calendarMonth2 = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + 1,
        1,
      );
      _notesController.clear();
    } else if (source != null &&
        (source['action'] ?? '').toString().isNotEmpty) {
      _editingId = (_editingRecord?['id'] ?? source['id'])?.toString();
      _timeOffType = source['action'].toString();
      _selectedDates = TimeOffService.selectedDatesForRecord(source).toSet();
      _syncSelectionBounds();
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
      _calendarMonth2 = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + 1,
        1,
      );
    }

    _timeOffType = TimeOffService.normalizeLeaveType(_timeOffType);

    if (!_leaveTypeOptions.any((o) => o['value'] == _timeOffType)) {
      _timeOffType = 'Annual Leave';
    }
    if (!_isAggregateOverview) {
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);

      _calendarMonth2 = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + 1,
        1,
      );
    }
  }

  void _markFormClean() {
    _hasTypeChanged = false;
    _hasDateSelectionChanged = false;
    _hasNotesChanged = false;
  }

  bool get _currentHasUnsavedChanges => hasUnsavedTimeOffChanges(
    hasSelectedDates: _hasDateSelectionChanged,
    hasNotes: _hasNotesChanged,
    isEditing: _editingId != null,
    typeChanged: _hasTypeChanged,
    datesChanged: _hasDateSelectionChanged,
  );

  bool get _hasUnsavedChanges =>
      _currentHasUnsavedChanges ||
      _pendingDrafts.values.any((draft) => draft.hasChanges);

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

  List<DateTime> get _sortedSelectedDates {
    final dates = _selectedDates.toList()..sort();
    return dates;
  }

  void _syncSelectionBounds() {
    final dates = _sortedSelectedDates;
    if (dates.isEmpty) {
      return;
    }
    _startDate = dates.first;
    _endDate = dates.last;
  }

  void _loadWorkers() {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
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
        if (widget.initialWorker != null) {
          _selectedWorker = _workers.firstWhere(
            (worker) => _sameWorker(worker, widget.initialWorker!),
            orElse: () => widget.initialWorker!,
          );
        } else if (_workers.isNotEmpty) {
          if (_selectedWorker == null) {
            _selectedWorker = null;
          } else {
            final idx = _workers.indexWhere(
              (worker) => _sameWorker(worker, _selectedWorker!),
            );
            _selectedWorker = idx != -1 ? _workers[idx] : null;
          }
        } else {
          _selectedWorker = null;
        }
      });
    } else {
      _workersSub = _firestore.workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workers = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            if (widget.initialWorker != null) {
              final initWorkerId = (widget.initialWorker!['workerId'] ?? '')
                  .toString()
                  .trim();
              final initEmail = (widget.initialWorker!['email'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final match = _workers.firstWhere((w) {
                final wId = (w['workerId'] ?? w['id'] ?? '').toString().trim();
                final wEmail = (w['email'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                return (initWorkerId.isNotEmpty && initWorkerId == wId) ||
                    (initEmail.isNotEmpty && initEmail == wEmail);
              }, orElse: () => widget.initialWorker!);
              _selectedWorker = match;
            } else if (_workers.isNotEmpty) {
              if (_selectedWorker == null) {
                _selectedWorker = null;
              } else {
                final idx = _workers.indexWhere(
                  (worker) => _sameWorker(worker, _selectedWorker!),
                );
                _selectedWorker = idx != -1 ? _workers[idx] : null;
              }
            } else {
              _selectedWorker = null;
            }

            if (_editingRecord != null) {
              _editingId = _editingRecord!['id']?.toString();
            }
          });
          _loadTimeoffForSelectedWorker();
        }
      }, onError: (e) {});
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
                  (day) => day >= DateTime.monday && day <= DateTime.sunday,
                )
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
  }

  Future<void> _loadTimeoffForSelectedWorker() async {
    final worker = _selectedWorker;
    if (worker == null) {
      await _timeoffSub?.cancel();
      await _attendanceSub?.cancel();
      _timeoffSub = null;
      _attendanceSub = null;
      _watchedTimeoffWorkerId = '';
      if (mounted) setState(() => _timeoffRecords = []);
      return;
    }
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    if (workerId.isEmpty) {
      await _timeoffSub?.cancel();
      await _attendanceSub?.cancel();
      _timeoffSub = null;
      _attendanceSub = null;
      _watchedTimeoffWorkerId = '';
      if (mounted) setState(() => _timeoffRecords = []);
      return;
    }
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      final rawTimeoff = DummyData.timeoff
          .where((r) => (r['workerId'] ?? r['id'] ?? '').toString() == workerId)
          .map((r) {
            final id = (r['id'] ?? '').toString().trim();
            if (id.isEmpty) {
              final syntheticId =
                  'timeoff_${r['workerId']}_${r['type']}_${r['startDate']}';
              r['id'] = syntheticId;
              return {...r, 'id': syntheticId};
            }
            return r;
          })
          .toList();
      final rawAttendance = DummyData.attendance
          .where((r) => (r['workerId'] ?? r['id'] ?? '').toString() == workerId)
          .toList();
      final records = TimeOffService.combineTimeOffAndAttendanceRecords(
        timeOffRecords: rawTimeoff,
        attendanceRecords: rawAttendance,
      );
      if (mounted) {
        setState(() {
          _timeoffRecords = records;
          _syncViewOnlyDatesForType();
        });
      }
      return;
    }
    if (_watchedTimeoffWorkerId == workerId && _timeoffSub != null && _attendanceSub != null) {
      return;
    }

    await _timeoffSub?.cancel();
    await _attendanceSub?.cancel();
    if (!mounted) return;
    _watchedTimeoffWorkerId = workerId;

    List<Map<String, dynamic>> latestTimeoffDocs = [];
    List<Map<String, dynamic>> latestAttendanceDocs = [];

    void updateCombinedRecords() {
      if (!mounted || _watchedTimeoffWorkerId != workerId) return;
      setState(() {
        _timeoffRecords = TimeOffService.combineTimeOffAndAttendanceRecords(
          timeOffRecords: latestTimeoffDocs,
          attendanceRecords: latestAttendanceDocs,
        );
        if (widget.viewOnly) {
          _syncViewOnlyDatesForType();
        } else if (_isAggregateOverview) {
          _syncAggregateDatesForType();
        } else {
          _syncOpenRecordFromLiveData();
        }
      });
    }

    _timeoffSub = _firestore
        .timeoffForWorkerStream(workerId)
        .listen(
          (snapshot) {
            latestTimeoffDocs = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            updateCombinedRecords();
          },
          onError: (Object error, StackTrace stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'TimeoffStream:$workerId',
            );
          },
        );

    _attendanceSub = _firestore
        .attendanceStreamForWorker(workerId)
        .listen(
          (snapshot) {
            latestAttendanceDocs = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            updateCombinedRecords();
          },
          onError: (Object error, StackTrace stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'AttendanceStream:$workerId',
            );
          },
        );
  }

  void _syncViewOnlyDatesForType() {
    if (!widget.viewOnly || _selectedWorker == null) return;
    final datesByType = TimeOffService.leaveDatesByTypeForWorker(
      _selectedWorkerForService,
      _timeoffRecords,
    );
    _selectedDates = (datesByType[_timeOffType] ?? const <DateTime>[]).toSet();
    _syncSelectionBounds();
  }

  void _syncAggregateDatesForType() {
    if (!_isAggregateOverview || _selectedWorker == null) return;
    final datesByType = TimeOffService.leaveDatesByTypeForWorker(
      _selectedWorkerForService,
      _timeoffRecords,
    );
    _selectedDates = (datesByType[_timeOffType] ?? const <DateTime>[]).toSet();
    _editingRecord = null;
    _editingId = null;
    _notesController.clear();
    _markFormClean();
  }

  void _syncOpenRecordFromLiveData() {
    if (_editingId == null || _hasUnsavedChanges) return;
    final liveRecord = _timeoffRecords.cast<Map<String, dynamic>?>().firstWhere(
      (record) => record?['id']?.toString() == _editingId,
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
    _editingId = record['id']?.toString();
    _timeOffType = TimeOffService.leaveType(record);
    _selectedDates = TimeOffService.selectedDatesForRecord(
      record,
    ).map(_dateOnly).toSet();
    _notesController.text = (record['notes'] ?? '').toString();
    if (_selectedDates.isEmpty) {
      _startDate = DateTime.now();
      _endDate = DateTime.now();
    } else {
      _syncSelectionBounds();
    }
    if (!preserveCalendarMonth) {
      _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
      _calendarMonth2 = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + 1,
        1,
      );
    }
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

      final newDraftKey = _draftKeyFor(null, normalizedType);
      final draft = _pendingDrafts[newDraftKey];
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
    });
  }

  String _getMonthName(int month) {
    return DateFormat(
      'MMMM',
      context.locale.toString(),
    ).format(DateTime(2024, month));
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  Map<String, dynamic> get _selectedWorkerForService {
    final worker = _selectedWorker;
    if (worker == null || _isGuest) return worker ?? <String, dynamic>{};

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    if (workerId.isEmpty) return worker;

    return {...worker, 'id': workerId, 'workerId': workerId};
  }

  Map<String, dynamic>? _holidayForDate(DateTime date) {
    for (final holiday in _holidays) {
      if (holiday['isEnabled'] == false) continue;
      final storedDate = AppDateUtils.holidayRecordDate(
        holiday,
        fallbackYear: date.year,
      );
      if (storedDate == null ||
          storedDate.day != date.day ||
          storedDate.month != date.month) {
        continue;
      }
      if (_isGuest) return holiday;

      final isRecurring = holiday['isRecurring'] == true;
      final holidayYear = storedDate.year;
      if (isRecurring || holidayYear == 0 || holidayYear == date.year) {
        return holiday;
      }
    }
    return null;
  }

  bool _isNonWorkingDate(DateTime date) {
    return !_companyWorkingDays.contains(date.weekday) ||
        _holidayForDate(date) != null;
  }

  int get _selectedDaysCount => _selectedDates.length;

  bool get _isPaidLeave => _paidLeaveTypes.contains(_timeOffType);

  bool get _usesPaidAllowance => _isGuest || _isPaidLeave;

  int _baseAvailableDaysForType(String type) {
    if (_selectedWorker == null) return 0;
    final base = TimeOffService.availableBalanceForEditingRecord(
      _selectedWorkerForService,
      _timeoffRecords,
      type,
      _editingRecord,
    );
    if (!_isAggregateOverview) return base;

    final assignedDates =
        TimeOffService.assignedLeaveDatesForWorkerByType(
          _selectedWorkerForService,
          _timeoffRecords,
        )[TimeOffService.normalizeLeaveType(type)]?.length ??
        0;
    final limit = TimeOffService.configuredLimitForType(
      _selectedWorkerForService,
      type,
    );
    return (base + assignedDates).clamp(0, limit);
  }

  int _availableDaysForType(String type) {
    if (widget.viewOnly) {
      return TimeOffService.remainingForType(
        _selectedWorkerForService,
        _timeoffRecords,
        type,
      );
    }
    final base = _baseAvailableDaysForType(type);
    final normType = TimeOffService.normalizeLeaveType(type);

    int currentlySelected = 0;
    if (TimeOffService.normalizeLeaveType(_timeOffType) == normType) {
      currentlySelected = _selectedDates.length;
    } else {
      final existingDraft = _pendingDrafts.values.cast<PendingTimeOffDraft?>().firstWhere(
        (d) => TimeOffService.normalizeLeaveType(d?.leaveType ?? '') == normType,
        orElse: () => null,
      );
      currentlySelected = existingDraft?.selectedDates.length ?? 0;
      if (currentlySelected == 0 && _selectedDates.isNotEmpty) {
        currentlySelected = _selectedDates.length;
      }
    }

    return projectedTimeOffBalance(
      availableDays: base,
      requestedDays: currentlySelected,
    );
  }



  int get _baseAvailableDays => _baseAvailableDaysForType(_timeOffType);

  int get _availableDays => _availableDaysForType(_timeOffType);

  bool get _requestedDaysExceedAvailable =>
      !widget.viewOnly &&
      _usesPaidAllowance &&
      _selectedDaysCount > _baseAvailableDays;

  String get _localizedSelectedLeaveType {
    final normalized = TimeOffService.normalizeLeaveType(_timeOffType);
    final option = _leaveTypeOptions.cast<Map<String, String>?>().firstWhere(
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
      _selectedWorkerForService,
      _timeOffType,
    );
  }

  String get _insufficientBalanceMessage {
    final availableDays = _availableDays;
    final key = availableDays == 0
        ? 'no_leave_days_available'
        : availableDays == 1
        ? 'only_one_leave_day_available'
        : 'only_leave_days_available';
    return key.tr(
      namedArgs: {
        'count': '$availableDays',
        'type': _localizedSelectedLeaveType,
      },
    );
  }

  int get _requestedDays => widget.viewOnly
      ? _selectedDaysCount
      : _requestedDaysExceedAvailable
      ? 0
      : _selectedDaysCount;

  int get _summaryRequestedDays {
    if (_selectedWorker == null) return 0;
    if (_isAggregateOverview) return _selectedDaysCount;
    return TimeOffService.projectedAssignedDaysForEditingRecord(
      _selectedWorkerForService,
      _timeoffRecords,
      _timeOffType,
      _editingRecord,
      _selectedDaysCount,
    );
  }

  int get _remainingDaysAfterRequest {
    if (_selectedWorker == null) return 0;
    return (_displayedLeaveBalance - _summaryRequestedDays).clamp(0, 9999);
  }

  List<(DateTime, String)> _allSelectedEntries() {
    final entries = <(DateTime, String)>[];
    final seen = <DateTime>{};
    for (final d in _sortedSelectedDates) {
      final key = _dateOnly(d);
      if (seen.add(key)) entries.add((d, _timeOffType));
    }
    for (final draft in _pendingDrafts.values) {
      for (final d in draft.selectedDates.toList()..sort()) {
        final key = _dateOnly(d);
        if (seen.add(key)) entries.add((d, draft.leaveType));
      }
    }
    return entries;
  }

  int get _allTypesSelectedDaysCount => _allSelectedEntries().length;

  String get _allTypesSelectedDatesSummary {
    final entries = _allSelectedEntries();
    if (entries.isEmpty) return 'select_date'.tr();
    final labels = entries
        .map(
          (e) =>
              '${LocalizationHelper.localizeLeaveType(e.$2)} ${_formatDate(e.$1)}',
        )
        .toList();
    final visible = labels.take(3).join(', ');
    final remaining = labels.length - 3;
    return remaining > 0 ? '$visible +$remaining' : visible;
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

  Future<bool> _confirmDiscardChanges() async {
    final currentContext = context;
    if (!_hasUnsavedChanges) {
      return true;
    }

    if (!mounted) return false;

    final shouldDiscard = await showGeneralDialog<bool>(
      context: currentContext,
      barrierDismissible: true,
      barrierLabel: 'UnsavedChangesDialog',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => const SizedBox(),
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 12 * animation.value,
            sigmaY: 12 * animation.value,
          ),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: curve,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.warning_rounded,
                            color: Color(0xFFEF4444),
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'discard_changes'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'unsaved_changes_message'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                          fontFamily: 'SF Pro Display',
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(ctx, false),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'cancel'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(ctx, true),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'discard'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _confirmDiscardChanges();
        if (shouldLeave && mounted) {
          if (!context.mounted) return;
          widget.onBack();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        _buildLeaveLegendItem(
                          'Annual Leave',
                          LeaveColors.annual,
                        ),
                        const SizedBox(width: 16),
                        _buildLeaveLegendItem('Sick Leave', LeaveColors.sick),
                        const SizedBox(width: 16),
                        _buildLeaveLegendItem(
                          'Casual Leave',
                          LeaveColors.casual,
                        ),
                        const SizedBox(width: 16),
                        _buildLeaveLegendItem(
                          'Medical Leave',
                          LeaveColors.medical,
                        ),
                      ],
                    ),
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
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.only(left: 32, right: 32, top: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final shouldLeave = await _confirmDiscardChanges();
              if (shouldLeave) {
                widget.onBack();
              }
            },
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
            child: const UserAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    if (_selectedWorker == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_off_rounded,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
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
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
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
            child: _buildUnifiedDaysGrid(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.touch_app_outlined,
                size: 18,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (widget.viewOnly ? 'selected_dates' : 'tap_dates_to_select')
                      .tr(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontFamily: 'SF Pro Display',
                  ),
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
                      _syncSelectionBounds();
                    });
                  },
                  child: Text('clear_selection'.tr()),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _buildNotesAndSummary(),
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
          child: _buildLabeledDropdown('time_off_type'.tr(), _timeOffType),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'selected_dates'.tr(),
            _allTypesSelectedDatesSummary,
            onTap: () {
              if (_allSelectedEntries().isEmpty) return;
              _showSelectedDatesListDialog(context);
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'selected_days'.tr(),
            '$_allTypesSelectedDaysCount',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0247C4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
              ),
              onPressed:
                  (widget.viewOnly ||
                      _selectedWorker == null ||
                      _isLoading ||
                      _isAggregateOverview ||
                      !_hasUnsavedChanges)
                  ? null
                  : () {
                      final isGuest =
                          _authService.currentUser?.isAnonymous ?? false;
                      if (isGuest) {
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
              data: ThemeData(
                canvasColor: Colors.white,
                dropdownMenuTheme: const DropdownMenuThemeData(
                  inputDecorationTheme: InputDecorationTheme(
                    labelStyle: TextStyle(color: Colors.black),
                  ),
                ),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                dropdownColor: Colors.white,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 14,
                  color: Colors.black,
                ),
                selectedItemBuilder: (context) {
                  return _leaveTypeOptions.map((option) {
                    final label = option['labelKey']!.tr();
                    final typeVal = option['value']!;
                    final avail = _availableDaysForType(typeVal);
                    final displayLabel =
                        (_selectedWorker != null && avail < 999)
                        ? '$label ($avail)'
                        : label;
                    final textColor = LeaveColors.getTextColor(typeVal);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                items: _leaveTypeOptions.map((option) {
                  final label = option['labelKey']!.tr();
                  final typeVal = option['value']!;
                  final avail = _availableDaysForType(typeVal);

                  final displayLabel = (_selectedWorker != null && avail < 999)
                      ? '$label ($avail)'
                      : label;
                  final textColor = LeaveColors.getTextColor(typeVal);
                  return DropdownMenuItem<String>(
                    value: typeVal,
                    child: Text(
                      displayLabel,
                      style: TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
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

  Widget _buildLabeledInput(String label, String value, {VoidCallback? onTap}) {
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
          fontFamily: 'SF Pro Display',
        ),
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

  Widget _buildCalendar(DateTime monthDate, {required bool isStartCalendar}) {
    String monthYear = '${_getMonthName(monthDate.month)} ${monthDate.year}'
        .toUpperCase();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _calendarContentWidth),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () {
                    if (isStartCalendar) {
                      final newMonth = DateTime(
                        _calendarMonth.year,
                        _calendarMonth.month - 1,
                        1,
                      );
                      if (newMonth.year != DateTime.now().year) return;
                      setState(() {
                        _calendarMonth = newMonth;
                      });
                    } else {
                      final newMonth = DateTime(
                        _calendarMonth2.year,
                        _calendarMonth2.month - 1,
                        1,
                      );
                      if (newMonth.year != DateTime.now().year) return;
                      setState(() {
                        _calendarMonth2 = newMonth;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  monthYear,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () {
                    if (isStartCalendar) {
                      final newMonth = DateTime(
                        _calendarMonth.year,
                        _calendarMonth.month + 1,
                        1,
                      );
                      if (newMonth.year != DateTime.now().year) return;
                      setState(() {
                        _calendarMonth = newMonth;
                      });
                    } else {
                      final newMonth = DateTime(
                        _calendarMonth2.year,
                        _calendarMonth2.month + 1,
                        1,
                      );
                      if (newMonth.year != DateTime.now().year) return;
                      setState(() {
                        _calendarMonth2 = newMonth;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildWeekdayRow(),
            const SizedBox(height: 8),
            _buildDaysGrid(monthDate),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekdayRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildWeekday('weekday_sun'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_mon'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_tue'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_wed'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_thu'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_fri'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_sat'.tr(), const Color(0xFF0247C4)),
      ],
    );
  }

  Widget _buildWeekday(String day, Color color) {
    String shortDay = day;
    if (shortDay.length > 3) shortDay = shortDay.substring(0, 3);

    return Center(
      child: Container(
        width: 50,
        height: 25,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
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
      ),
    );
  }

  Widget _buildUnifiedDaysGrid() {
    const cellExtent = 54.0;
    const calendarWidth = 7 * cellExtent;
    const containerWidth = calendarWidth + 32;

    const calendarOuterWidth = _calendarContentWidth + 32.0 + 2.0;
    const naturalRowWidth = calendarOuterWidth * 2 + 24.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double gridScale = constraints.maxWidth < naturalRowWidth
            ? constraints.maxWidth / naturalRowWidth
            : 1.0;

        Offset toGridSpace(Offset pos) => gridScale == 1.0
            ? pos
            : Offset(pos.dx / gridScale, pos.dy / gridScale);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanDown: (details) {
            final pos = toGridSpace(details.localPosition);
            final isSecond = pos.dx > containerWidth + 24;
            final monthDate = isSecond ? _calendarMonth2 : _calendarMonth;
            final adjustedPos = isSecond
                ? Offset(pos.dx - containerWidth - 24, pos.dy)
                : pos;
            _dragAnchorDate = _dateAtGridPosition(monthDate, adjustedPos);
            _lastDragDate = null;
            _selectionBeforeDrag = Set<DateTime>.from(_selectedDates);
            _dragExceededAvailableDays = false;
            _dragStartPosition = pos;
            _dragMoved = false;
          },
          onPanUpdate: (details) {
            final pos = toGridSpace(details.localPosition);
            final startPos = _dragStartPosition;
            if (startPos != null && !_dragMoved) {
              final dx = (pos.dx - startPos.dx).abs();
              final dy = (pos.dy - startPos.dy).abs();
              if (dx > 18 || dy > 18) _dragMoved = true;
            }
            if (!_dragMoved) return;

            final anchor = _dragAnchorDate;
            final isSecond = pos.dx > containerWidth + 24;
            final monthDate = isSecond ? _calendarMonth2 : _calendarMonth;
            final adjustedPos = isSecond
                ? Offset(pos.dx - containerWidth - 24, pos.dy)
                : pos;
            final current = _dateAtGridPosition(monthDate, adjustedPos);
            if (anchor == null || current == null || current == _lastDragDate) {
              return;
            }
            _lastDragDate = current;

            final candidate = Set<DateTime>.from(_selectionBeforeDrag);
            final isDragRemoving = _selectionBeforeDrag.contains(
              _dragAnchorDate,
            );
            var exceededAvailableDays = false;
            final today = DateTime.now();
            final todayDate = DateTime(today.year, today.month, today.day);
            for (final date in TimeOffService.inclusiveDateRange(
              anchor,
              current,
            )) {
              if (_isNonWorkingDate(date)) continue;
              if (isDragRemoving) {
                final isPastDate = date.isBefore(todayDate);
                if (isPastDate) continue;
                candidate.remove(date);
              } else {
                if (candidate.contains(date)) continue;

                if (_selectedWorker != null) {
                  final savedLeave = TimeOffService.activeLeaveForWorker(
                    _selectedWorker!,
                    _timeoffRecords,
                    onDate: date,
                    excludingRecordId: _editingId,
                  );
                  if (savedLeave != null) continue;
                }

                if (_usesPaidAllowance &&
                    candidate.length >= _baseAvailableDays) {
                  if (!_isGuest) exceededAvailableDays = true;
                  break;
                }
                candidate.add(date);
              }
            }

            setState(() {
              _selectedDates = candidate;
              _hasDateSelectionChanged = true;
              _dragExceededAvailableDays = exceededAvailableDays;
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
                _buildCalendar(_calendarMonth, isStartCalendar: true),
                const SizedBox(width: 24),
                _buildCalendar(_calendarMonth2, isStartCalendar: false),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDaysGrid(DateTime monthDate) {
    List<Widget> rows = [];
    int daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    int firstWeekday = DateTime(monthDate.year, monthDate.month, 1).weekday;
    int startIndex = firstWeekday == 7 ? 0 : firstWeekday;

    int currentDay = 1;

    for (int i = 0; i < 6; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        if (i == 0 && j < startIndex) {
          rowChildren.add(_buildDayCell(''));
        } else if (currentDay <= daysInMonth) {
          DateTime cellDate = DateTime(
            monthDate.year,
            monthDate.month,
            currentDay,
          );

          final bool isSelected = _selectedDates.contains(cellDate);

          rowChildren.add(
            _buildDayCell(
              '$currentDay',
              isSelected: isSelected,
              date: cellDate,
              isDisabled: _isNonWorkingDate(cellDate),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(_buildDayCell(''));
        }
        if (j < 6) {
          rowChildren.add(const SizedBox(width: 4));
        }
      }
      rows.add(Row(mainAxisSize: MainAxisSize.min, children: rowChildren));
      if (currentDay > daysInMonth && i >= 5) {
        break;
      }
      if (i < 5) {
        rows.add(const SizedBox(height: 4));
      }
    }
    return Column(children: rows);
  }

  DateTime? _dateAtGridPosition(DateTime monthDate, Offset position) {
    const cellExtent = 54.0;
    const headerHeight = 93.0;
    const calendarPadding = 17.0;
    final adjustedDy = position.dy - headerHeight;
    final adjustedDx = position.dx - calendarPadding;
    if (adjustedDy < 0 || adjustedDx < 0) return null;
    final column = (adjustedDx / cellExtent).floor();
    final row = (adjustedDy / cellExtent).floor();
    if (column < 0 || column > 6 || row < 0 || row > 5) return null;

    final firstWeekday = DateTime(monthDate.year, monthDate.month, 1).weekday;
    final startIndex = firstWeekday == 7 ? 0 : firstWeekday;
    final day = (row * 7) + column - startIndex + 1;
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    if (day < 1 || day > daysInMonth) return null;
    return DateTime(monthDate.year, monthDate.month, day);
  }

  void _finishDateDrag() {
    if (_dragExceededAvailableDays) {
      FlashySnackBar.show(
        context,
        message: _insufficientBalanceMessage,
        isError: true,
      );
    }
    _dragAnchorDate = null;
    _lastDragDate = null;
    _selectionBeforeDrag = <DateTime>{};
    _dragExceededAvailableDays = false;
    _dragStartPosition = null;
    _dragMoved = false;
  }

  Future<void> _toggleDate(DateTime date) async {
    final selectedDate = _dateOnly(date);
    final isRemoving = _selectedDates.contains(selectedDate);
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final isPastDate = selectedDate.isBefore(todayStart);

    // Block any modification to past dates — neither add nor remove allowed
    if (isPastDate) {
      FlashySnackBar.show(
        context,
        message: 'past_time_off_edit_blocked'.tr(),
        isError: true,
      );
      return;
    }

    if (_isAggregateOverview) {
      if (!isRemoving || _selectedWorker == null) return;
      final owningRecord = TimeOffService.activeLeaveForWorker(
        _selectedWorkerForService,
        _timeoffRecords,
        onDate: selectedDate,
      );
      if (owningRecord == null ||
          !TimeOffService.recordHasLeaveType(owningRecord, _timeOffType)) {
        return;
      }
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      if (selectedDate.isBefore(todayStart)) {
        FlashySnackBar.show(
          context,
          message: 'past_time_off_edit_blocked'.tr(),
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _isAggregateOverview = false;
        _applyEditingRecord(owningRecord, preserveCalendarMonth: true);
        _selectedDates.remove(selectedDate);
        _hasDateSelectionChanged = true;
        _syncSelectionBounds();
      });
      return;
    }

    if (!isRemoving && _isNonWorkingDate(selectedDate)) {
      FlashySnackBar.show(
        context,
        message: 'time_off_non_working_day_blocked'.tr(),
        isError: true,
      );
      return;
    }

    if (!isRemoving && _selectedWorker != null) {
      final existingLeave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: selectedDate,
        excludingRecordId: _editingId,
      );
      if (existingLeave != null) {
        if (isPastDate) {
          FlashySnackBar.show(
            context,
            message: 'past_time_off_edit_blocked'.tr(),
            isError: true,
          );
          return;
        }

        if (!mounted) return;
        _stashCurrentDraft();
        setState(() {
          _applyEditingRecord(existingLeave, preserveCalendarMonth: true);
          _selectedDates.remove(selectedDate);
          _hasDateSelectionChanged = true;
          _syncSelectionBounds();
        });
        return;
      }
    }

    if (!isRemoving && _usesPaidAllowance && _availableDays <= 0) {
      FlashySnackBar.show(
        context,
        message: _insufficientBalanceMessage,
        isError: true,
      );
      return;
    }
    setState(() {
      if (isRemoving) {
        _selectedDates.remove(selectedDate);
      } else {
        _selectedDates.add(selectedDate);
      }
      _hasDateSelectionChanged = true;
      _syncSelectionBounds();
    });
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

    Map<String, dynamic>? savedLeave;
    if (!isSelected && date != null && _selectedWorker != null) {
      final candidateLeave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: date,
        excludingRecordId: _editingId,
      );
      if (candidateLeave != null) {
        final recId = (candidateLeave['id'] ?? '').toString().trim();
        final draft = recId.isNotEmpty ? _pendingDrafts[recId] : null;
        if (draft != null) {
          if (draft.selectedDates.contains(date)) {
            savedLeave = candidateLeave;
          }
        } else {
          savedLeave = candidateLeave;
        }
      }
    }
    if (!isSelected && savedLeave == null && date != null) {
      for (final draft in _pendingDrafts.values) {
        final draftId = (draft.editingId ?? '').trim();
        if ((draftId.isEmpty || draftId != (_editingId ?? '').trim()) &&
            draft.selectedDates.contains(date)) {
          savedLeave = {
            'action': draft.leaveType,
            'type': draft.leaveType,
            'id': draft.editingId,
          };
          break;
        }
      }
    }
    final savedType = savedLeave != null
        ? (savedLeave['action'] ?? savedLeave['type']).toString()
        : null;
    final isCellHighlighted = isSelected || savedLeave != null;
    final effectiveType = isSelected ? _timeOffType : savedType;
    final effectiveColor = effectiveType != null
        ? LeaveColors.getColor(effectiveType)
        : null;

    final bgColor = isCellHighlighted
        ? effectiveColor!
        : (isDisabled ? const Color(0xFFF1F5F9) : Colors.transparent);

    final borderColor = isCellHighlighted
        ? effectiveColor!
        : Colors.grey.shade300;

    final textColor = isDisabled && !isCellHighlighted
        ? const Color(0xFFB0B7C3)
        : (isCellHighlighted ? const Color(0xFFFFFFFF) : Colors.black);

    final tooltipType = effectiveType ?? _timeOffType;
    final tooltipOption = _leaveTypeOptions
        .cast<Map<String, String>?>()
        .firstWhere(
          (option) => option?['value'] == tooltipType,
          orElse: () => null,
        );
    final tooltipTypeLabel = tooltipOption?['labelKey']?.tr() ?? tooltipType;

    final tooltipDate = date == null ? '' : _formatDate(date);
    final tooltipMessage = '$tooltipTypeLabel\n$tooltipDate';
    final tooltipColor = LeaveColors.getColor(tooltipType);

    return Center(
      child: Tooltip(
        message: tooltipMessage,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tooltipColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: tooltipColor.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
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
                  if (!_dragMoved) {
                    unawaited(_toggleDate(date));
                  }
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
    Widget notesWidget = Column(
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: TextField(
            controller: _notesController,
            readOnly: widget.viewOnly || _isAggregateOverview,
            onChanged: (_) {
              setState(() {
                _hasNotesChanged = true;
              });
            },
            maxLines: null,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontFamily: 'SF Pro Display',
            ),
            decoration: InputDecoration.collapsed(
              hintText: 'please_enter_notes'.tr(),
              hintStyle: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      ],
    );

    Widget summaryWidget = Column(
      children: [
        _buildSummaryRow(
          _availableLeaveLabel,
          '$_displayedLeaveBalance',
          _displayedLeaveBalance > 0 ? Colors.black : Colors.red,
        ),
        _buildSummaryRow(
          'requested_days'.tr(),
          '$_summaryRequestedDays',
          Colors.black,
        ),
        _buildSummaryRow(
          'remaining_days'.tr(),
          '$_remainingDaysAfterRequest',
          _remainingDaysAfterRequest >= 0 ? Colors.black : Colors.red,
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 70, child: notesWidget),
        const SizedBox(width: 24),
        Expanded(
          flex: 30,
          child: Padding(
            padding: const EdgeInsets.only(top: 32),
            child: summaryWidget,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, Color valueColor) {
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
              fontFamily: 'SF Pro Display',
            ),
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

  String _getWorkerPhone(Map<String, dynamic> w) {
    for (final key in ['phone', 'contact']) {
      final val = w[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        return val.toString().trim();
      }
    }
    return '';
  }

  bool _isEligibleWorker(Map<String, dynamic> worker) {
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

  String _dateOnlyString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _handleSave() async {
    if (widget.viewOnly) return;
    if (_isLoading) return;
    if (!_hasUnsavedChanges) return;

    _stashCurrentDraft();
    if (_pendingDrafts.isNotEmpty) {
      await _savePendingDrafts();
      return;
    }
    // Block if editing existing record and past dates were removed
    if (_editingRecord != null) {
      final oldDates = TimeOffService.selectedDatesForRecord(_editingRecord!);
      if (TimeOffService.hasPastDateModification(
        oldDates: oldDates,
        newDates: _selectedDates,
      )) {
        FlashySnackBar.show(
          context,
          message: 'past_time_off_edit_blocked'.tr(),
          isError: true,
        );
        return;
      }
    }

    // Block fresh assignment if any selected date is in the past
    if (_editingRecord == null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (_selectedDates.any((d) => d.isBefore(today))) {
        FlashySnackBar.show(
          context,
          message: 'past_time_off_edit_blocked'.tr(),
          isError: true,
        );
        return;
      }
    }

    if (_selectedWorker == null && _selectedDates.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_all_fields'.tr(),
        isError: true,
      );
      return;
    }

    if (_selectedWorker == null) {
      FlashySnackBar.show(
        context,
        message: 'please_select_worker_first'.tr(),
        isError: true,
      );
      return;
    }

    if (!_isEligibleWorker(_selectedWorker!)) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }

    if (_selectedDates.isEmpty && _editingId != null) {
      setState(() => _isLoading = true);
      try {
        final workerIdentity =
            _selectedWorker!['workerId'] ?? _selectedWorker!['id'] ?? '';
        final workerId = workerIdentity.toString().trim();
        if (workerId.isEmpty) throw StateError('Missing worker id');
        if (_isGuest) {
          final recordIndex = DummyData.timeoff.indexWhere(
            (record) => record['id']?.toString() == _editingId,
          );
          if (recordIndex == -1) {
            throw StateError('Time off record does not exist');
          }
          final oldRecord = DummyData.timeoff[recordIndex];
          final workerIndex = DummyData.workers.indexWhere(
            (worker) =>
                (worker['workerId'] ?? worker['id'] ?? '').toString().trim() ==
                workerId,
          );
          if (workerIndex != -1) {
            final balances = Map<String, dynamic>.from(
              TimeOffService.canonicalWorkerLeaveFields(
                    DummyData.workers[workerIndex],
                  )['leaveBalances']
                  as Map,
            );
            final oldField = switch (TimeOffService.leaveType(oldRecord)) {
              'Annual Leave' => 'annualLeave',
              'Sick Leave' => 'sickLeave',
              'Casual Leave' => 'casualLeave',
              'Medical Leave' => 'medicalLeave',
              _ => '',
            };
            if (oldField.isNotEmpty) {
              final current =
                  int.tryParse(balances[oldField]?.toString() ?? '0') ?? 0;
              balances[oldField] =
                  current +
                  TimeOffService.selectedDatesForRecord(oldRecord).length;
              DummyData.workers[workerIndex].addAll(
                TimeOffService.canonicalWorkerLeaveFields(
                  DummyData.workers[workerIndex],
                  remainingBalances: balances,
                ),
              );
            }
          }
          DummyData.timeoff[recordIndex] = {
            ...oldRecord,
            'status': 'Cancelled',
          };
          await DummyData.saveToPrefs();
        } else {
          await _firestore.cancelTimeOffWithWorkerBalance(
            timeOffId: _editingId!,
            workerId: workerId,
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
          FlashySnackBar.show(
            context,
            message: 'past_time_off_edit_blocked'.tr(),
            isError: true,
          );
        }
      } catch (_) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'assign_time_off_failed'.tr(),
            isError: true,
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    if (_selectedDates.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_select_dates'.tr(),
        isError: true,
      );
      return;
    }

    if (_selectedDates.any(_isNonWorkingDate)) {
      FlashySnackBar.show(
        context,
        message: 'time_off_non_working_day_blocked'.tr(),
        isError: true,
      );
      return;
    }

    if (TimeOffService.hasOverlappingApprovedLeave(
      _isGuest ? _selectedWorker! : _selectedWorkerForService,
      _timeoffRecords,
      _selectedDates,
      excludingRecordId: _editingId,
    )) {
      FlashySnackBar.show(
        context,
        message: 'time_off_dates_overlap'.tr(),
        isError: true,
      );
      return;
    }

    if (_requestedDaysExceedAvailable) {
      FlashySnackBar.show(
        context,
        message: _insufficientBalanceMessage,
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      final workerIdentity =
          _selectedWorker!['workerId'] ?? _selectedWorker!['id'] ?? '';
      final workerId = workerIdentity.toString().trim();
      if (!isGuest && workerId.isEmpty) {
        throw StateError('Missing worker id');
      }

      if (_editingRecord != null &&
          !TimeOffService.recordHasLeaveType(_editingRecord!, _timeOffType)) {
        throw StateError(
          'The selected leave type does not match the record being edited',
        );
      }

      final recordMap = <String, dynamic>{
        'workerId': isGuest ? workerIdentity : workerId,
        'name': _selectedWorker!['name'] ?? 'Worker',
        'email': _selectedWorker!['email'] ?? '',
        'position': _selectedWorker!['position'] ?? 'Worker',
        'contact': _getWorkerPhone(_selectedWorker!),
        'action': _timeOffType,
        'type': _timeOffType,

        'startDate': _dateOnlyString(_startDate),
        'endDate': _dateOnlyString(_endDate),
        'selectedDates': _sortedSelectedDates.map(_dateOnlyString).toList(),
        'notes': _notesController.text.trim(),
        'requestedDays': _requestedDays,
        'status': 'Approved',
        'isPaidLeave': _isPaidLeave,
        'workerName': _selectedWorker!['name'] ?? 'Worker',
        'workerAvatar': _selectedWorker!['profileImage'] ?? '',
      };

      final leaveField = switch (TimeOffService.normalizeLeaveType(
        _timeOffType,
      )) {
        'Annual Leave' => 'annualLeave',
        'Sick Leave' => 'sickLeave',
        'Casual Leave' => 'casualLeave',
        'Medical Leave' => 'medicalLeave',
        _ => '',
      };

      if (isGuest) {
        Map<String, dynamic>? previousGuestRecord;
        if (_editingId != null) {
          final idx = DummyData.timeoff.indexWhere(
            (t) => t['id'] == _editingId,
          );
          if (idx != -1) {
            previousGuestRecord = Map<String, dynamic>.from(
              DummyData.timeoff[idx],
            );
            DummyData.timeoff[idx] = {...DummyData.timeoff[idx], ...recordMap};
          }
        } else {
          DummyData.timeoff.insert(0, {
            ...recordMap,
            'id': 'guest_to_${DateTime.now().millisecondsSinceEpoch}',
          });
        }
        final workerIdx = DummyData.workers.indexWhere(
          (worker) =>
              (worker['email'] ?? '').toString().trim().toLowerCase() ==
              (_selectedWorker!['email'] ?? '').toString().trim().toLowerCase(),
        );
        if (workerIdx != -1) {
          final currentMap = Map<String, dynamic>.from(
            DummyData.workers[workerIdx]['leaveBalances'] as Map? ??
                {
                  'annualLeave':
                      int.tryParse(
                        (DummyData.workers[workerIdx]['availableAnnualLeaves'] ??
                                DummyData.workers[workerIdx]['annualLeaves'] ??
                                '0')
                            .toString(),
                      ) ??
                      0,
                  'sickLeave':
                      int.tryParse(
                        (DummyData.workers[workerIdx]['availableSickLeaves'] ??
                                DummyData.workers[workerIdx]['sickLeaves'] ??
                                '0')
                            .toString(),
                      ) ??
                      0,
                  'casualLeave':
                      int.tryParse(
                        (DummyData.workers[workerIdx]['availableCasualLeaves'] ??
                                DummyData.workers[workerIdx]['casualLeaves'] ??
                                '0')
                            .toString(),
                      ) ??
                      0,
                  'medicalLeave':
                      int.tryParse(
                        (DummyData.workers[workerIdx]['availableMedicalLeaves'] ??
                                DummyData.workers[workerIdx]['medicalLeaves'] ??
                                '0')
                            .toString(),
                      ) ??
                      0,
                },
          );
          final currentVal =
              int.tryParse(currentMap[leaveField]?.toString() ?? '0') ?? 0;
          if (previousGuestRecord != null) {
            final oldField = switch (TimeOffService.leaveType(
              previousGuestRecord,
            )) {
              'Annual Leave' => 'annualLeave',
              'Sick Leave' => 'sickLeave',
              'Casual Leave' => 'casualLeave',
              'Medical Leave' => 'medicalLeave',
              _ => '',
            };
            final oldDays = TimeOffService.selectedDatesForRecord(
              previousGuestRecord,
            ).length;
            if (oldField.isNotEmpty && oldDays > 0) {
              final oldBalance =
                  int.tryParse(currentMap[oldField]?.toString() ?? '0') ?? 0;
              currentMap[oldField] = oldBalance + oldDays;
            }
          }
          final restoredNewBalance =
              int.tryParse(currentMap[leaveField]?.toString() ?? '0') ??
              currentVal;
          final updatedVal = (restoredNewBalance - _requestedDays).clamp(
            0,
            999,
          );
          currentMap[leaveField] = updatedVal;
          DummyData.workers[workerIdx].addAll(
            TimeOffService.canonicalWorkerLeaveFields(
              DummyData.workers[workerIdx],
              remainingBalances: currentMap,
            ),
          );
        }
        await DummyData.saveToPrefs();
      } else {
        await _firestore.saveTimeOffWithWorkerBalance(
          timeOffId: _editingId,
          record: recordMap,
          workerId: workerId,
          leaveType: _timeOffType,
          requestedDays: _requestedDays,
        );
      }

      if (mounted) {
        setState(() {
          _editingRecord = null;
          _editingId = null;
          _selectedDates.clear();
          _startDate = DateTime.now();
          _endDate = DateTime.now();
          _notesController.clear();
          _timeOffType = 'Annual Leave';
          _markFormClean();
        });
        await _loadTimeoffForSelectedWorker();
        if (!mounted) return;
        FlashySnackBar.show(
          context,
          message:
              (_editingId == null
                      ? 'assign_time_off_success'
                      : 'update_time_off_success')
                  .tr(
                    namedArgs: {
                      'name': (_selectedWorker?['name'] ?? 'Worker').toString(),
                    },
                  ),
        );
        widget.onBack();
        return;
      }
    } on DuplicateTimeOffDateException {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'time_off_dates_overlap'.tr(),
          isError: true,
        );
      }
    } on PastTimeOffEditException {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'past_time_off_edit_blocked'.tr(),
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'assign_time_off_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePendingDrafts() async {
    final worker = _selectedWorker;
    if (worker == null) {
      FlashySnackBar.show(
        context,
        message: 'please_select_worker_first'.tr(),
        isError: true,
      );
      return;
    }
    if (!_isEligibleWorker(worker)) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }

    final workerIdentity = worker['workerId'] ?? worker['id'] ?? '';
    final workerId = workerIdentity.toString().trim();
    if (workerId.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'assign_time_off_failed'.tr(),
        isError: true,
      );
      return;
    }

    final drafts = _pendingDrafts.values
        .where((draft) => draft.hasChanges)
        .toList();
    final pendingDates = <DateTime>{};
    for (final draft in drafts) {
      if (draft.selectedDates.any(_isNonWorkingDate)) {
        FlashySnackBar.show(
          context,
          message: 'time_off_non_working_day_blocked'.tr(),
          isError: true,
        );
        return;
      }
      for (final date in draft.selectedDates) {
        if (!pendingDates.add(_dateOnly(date))) {
          FlashySnackBar.show(
            context,
            message: 'time_off_dates_overlap'.tr(),
            isError: true,
          );
          return;
        }
      }
      if (TimeOffService.hasOverlappingApprovedLeave(
        _selectedWorkerForService,
        _timeoffRecords,
        draft.selectedDates,
        excludingRecordId: draft.editingId,
      )) {
        FlashySnackBar.show(
          context,
          message: 'time_off_dates_overlap'.tr(),
          isError: true,
        );
        return;
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
          message: 'only_leave_days_available'.tr(
            namedArgs: {
              'count': '$available',
              'type': LocalizationHelper.localizeLeaveType(draft.leaveType),
            },
          ),
          isError: true,
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      await Future.wait(
        drafts.map((draft) async {
          if (draft.selectedDates.isEmpty && draft.editingId != null) {
            await _firestore.cancelTimeOffWithWorkerBalance(
              timeOffId: draft.editingId!,
              workerId: workerId,
            );
            return;
          }
          if (draft.selectedDates.isEmpty) return;

          final sortedDates = draft.selectedDates.toList()..sort();
          final record = <String, dynamic>{
            'workerId': workerId,
            'name': worker['name'] ?? 'Worker',
            'email': worker['email'] ?? '',
            'position': worker['position'] ?? 'Worker',
            'contact': _getWorkerPhone(worker),
            'action': draft.leaveType,
            'type': draft.leaveType,
            'startDate': _dateOnlyString(sortedDates.first),
            'endDate': _dateOnlyString(sortedDates.last),
            'selectedDates': sortedDates.map(_dateOnlyString).toList(),
            'notes': draft.notes,
            'requestedDays': sortedDates.length,
            'status': 'Approved',
            'isPaidLeave': _paidLeaveTypes.contains(draft.leaveType),
            'workerName': worker['name'] ?? 'Worker',
            'workerAvatar': worker['profileImage'] ?? '',
          };
          await _firestore.saveTimeOffWithWorkerBalance(
            timeOffId: draft.editingId,
            record: record,
            workerId: workerId,
            leaveType: draft.leaveType,
            requestedDays: sortedDates.length,
          );
        }),
      );

      if (!mounted) return;
      _pendingDrafts.clear();
      _markFormClean();
      FlashySnackBar.show(
        context,
        message: 'assign_time_off_success'.tr(
          namedArgs: {'name': (worker['name'] ?? 'Worker').toString()},
        ),
      );
      widget.onBack();
    } on DuplicateTimeOffDateException {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'time_off_dates_overlap'.tr(),
          isError: true,
        );
      }
    } on PastTimeOffEditException {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'past_time_off_edit_blocked'.tr(),
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'assign_time_off_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSelectedDatesListDialog(BuildContext context) {
    final entries = _allSelectedEntries();
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
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: const BoxDecoration(color: Color(0xFF004FDE)),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'selected_dates_count_title'.tr(
                                namedArgs: {'count': '${entries.length}'},
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
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
                        children:
                            [
                              'Annual Leave',
                              'Sick Leave',
                              'Casual Leave',
                              'Medical Leave',
                            ].map((type) {
                              final color = LeaveColors.getColor(type);
                              final count = entries
                                  .where((e) => e.$2 == type)
                                  .length;
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
                                  '${LocalizationHelper.localizeLeaveType(type)}: $count ${count == 1 ? 'day'.tr() : 'days'.tr()}',
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: entries.isEmpty
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
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: entries.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Color(0xFFEEEEEE),
                                ),
                                itemBuilder: (context, index) {
                                  final (date, type) = entries[index];
                                  final dayDisplayType =
                                      LocalizationHelper.localizeLeaveType(
                                        type,
                                      );
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE5EEFC),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
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
                                            DateFormat.yMMMd(
                                              localeName,
                                            ).format(date),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ),
                                        Text(
                                          DateFormat.EEEE(
                                            localeName,
                                          ).format(date),
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
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: LeaveColors.getBgColor(
                                                type,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              dayDisplayType,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: LeaveColors.getColor(
                                                  type,
                                                ),
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
          ),
        ],
      ),
    );
  }
}
