import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/preferences_service.dart';
import '../services/time_off_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/guest_restriction.dart';
import '../utils/time_off_unsaved_changes.dart';

import 'package:easy_localization/easy_localization.dart';
import '../widgets/notification_bell.dart';

class AssignTimeOffScreen extends StatefulWidget {
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
  State<AssignTimeOffScreen> createState() => _AssignTimeOffScreenState();
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

class _AssignTimeOffScreenState extends State<AssignTimeOffScreen> {
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

  @override
  void initState() {
    super.initState();
    if (widget.initialWorker != null) {
      _selectedWorker = widget.initialWorker;

      final hasAction = (widget.initialWorker!['action'] ?? '')
          .toString()
          .isNotEmpty;
      if (hasAction) {
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
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
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
    final source = _editingRecord ?? _selectedWorker;
    _hasTypeChanged = false;
    _hasDateSelectionChanged = false;
    _hasNotesChanged = false;
    if (source != null && (source['action'] ?? '').toString().isNotEmpty) {
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

    if (_selectedDates.isNotEmpty) {
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
    _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);

    _calendarMonth2 = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + 1,
      1,
    );
  }

  void _markFormClean() {
    _hasTypeChanged = false;
    _hasDateSelectionChanged = false;
    _hasNotesChanged = false;
  }

  bool get _hasUnsavedChanges => hasUnsavedTimeOffChanges(
    hasSelectedDates: _hasDateSelectionChanged,
    hasNotes: _hasNotesChanged,
    isEditing: _editingId != null,
    typeChanged: _hasTypeChanged,
    datesChanged: _hasDateSelectionChanged,
  );

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
      if (mounted) setState(() => _timeoffRecords = []);
      return;
    }
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    if (workerId.isEmpty) {
      if (mounted) setState(() => _timeoffRecords = []);
      return;
    }
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      final records = DummyData.timeoff
          .where((r) => (r['workerId'] ?? r['id'] ?? '').toString() == workerId)
          .toList();
      if (mounted) {
        setState(() {
          _timeoffRecords = records;
          _syncViewOnlyDatesForType();
        });
      }
      return;
    }
    try {
      final snapshot = await _firestore.getTimeoffForWorker(workerId);
      if (!mounted) return;
      setState(() {
        _timeoffRecords = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        _syncViewOnlyDatesForType();
      });
    } catch (_) {}
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

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

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
    final monthName = _monthNames[date.month - 1];
    for (final holiday in _holidays) {
      if (holiday['isEnabled'] == false) continue;
      final holidayDay = int.tryParse((holiday['day'] ?? '').toString());
      final holidayMonth = (holiday['month'] ?? '').toString();
      if (holidayDay != date.day || holidayMonth != monthName) continue;
      if (_isGuest) return holiday;

      final isRecurring = holiday['isRecurring'] == true;
      final holidayYear = int.tryParse((holiday['year'] ?? '').toString());
      if (isRecurring ||
          holidayYear == null ||
          holidayYear == 0 ||
          holidayYear == date.year) {
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
    final dbBalance = TimeOffService.getLeaveBalance(
      _selectedWorkerForService,
      type,
    );

    if (_editingRecord != null) {
      final originalType = TimeOffService.leaveType(_editingRecord!);
      final originalDaysCount = TimeOffService.selectedDatesForRecord(
        _editingRecord!,
      ).length;

      final normType = TimeOffService.normalizeLeaveType(type);
      final normOriginalType = TimeOffService.normalizeLeaveType(originalType);

      if (normType == normOriginalType) {
        return (dbBalance + originalDaysCount).clamp(0, 9999);
      }
    }
    return dbBalance.clamp(0, 9999);
  }

  int _availableDaysForType(String type) {
    if (widget.viewOnly) {
      return TimeOffService.getLeaveBalance(_selectedWorkerForService, type);
    }
    final base = _baseAvailableDaysForType(type);
    final normType = TimeOffService.normalizeLeaveType(type);
    final currentlySelected =
        (TimeOffService.normalizeLeaveType(_timeOffType) == normType)
        ? _selectedDates.length
        : 0;
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
    final key = availableDays == 1
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

  int get _remainingDaysAfterRequest {
    if (widget.viewOnly && _selectedWorker != null) {
      return TimeOffService.getLeaveBalance(
        _selectedWorkerForService,
        _timeOffType,
      );
    }
    if (!_isGuest && !_isPaidLeave) return _baseAvailableDays;
    return projectedTimeOffBalance(
      availableDays: _baseAvailableDays,
      requestedDays: _requestedDays,
    );
  }

  String get _selectedDatesSummary {
    final dates = _sortedSelectedDates;
    if (dates.isEmpty) return 'select_date'.tr();
    final visibleDates = dates.take(3).map(_formatDate).join(', ');
    final remaining = dates.length - 3;
    return remaining > 0 ? '$visibleDates +$remaining' : visibleDates;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _workersSub?.cancel();
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
              if (_selectedDates.isNotEmpty && !widget.viewOnly)
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
            _selectedDatesSummary,
            onTap: () {
              if (_selectedDates.isEmpty) return;
              showDialog(
                context: context,
                builder: (context) {
                  return Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    child: Container(
                      width: 420,
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
                            decoration: const BoxDecoration(
                              color: Color(0xFF004FDE),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'assign_time_off'.tr(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 30),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_selectedWorker != null) ...[
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.blue.shade100,
                                        child: Text(
                                          (_selectedWorker!['name'] ?? 'U')
                                              .toString()[0]
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: Color(0xFF004FDE),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (_selectedWorker!['name'] ?? '')
                                                  .toString(),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.email,
                                                  size: 12,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    (_selectedWorker!['email'] ??
                                                            '')
                                                        .toString(),
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey,
                                                      fontFamily:
                                                          'SF Pro Display',
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTimeOffMetricCard(
                                        icon: const Icon(
                                          Icons.category,
                                          color: Color(0xFF004FDE),
                                          size: 20,
                                        ),
                                        title: 'time_off_type'.tr(),
                                        value: _localizedSelectedLeaveType,
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
                                        title: _availableLeaveLabel,
                                        value: '$_displayedLeaveBalance',
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
                                          Icons.event,
                                          color: Color(0xFF004FDE),
                                          size: 20,
                                        ),
                                        title: 'requested_days'.tr(),
                                        value: '$_requestedDays',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTimeOffMetricCard(
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          color: Color(0xFF004FDE),
                                          size: 20,
                                        ),
                                        title: 'selected_days'.tr(),
                                        value: '$_selectedDaysCount',
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
                                          Icons.pie_chart,
                                          color: Color(0xFF004FDE),
                                          size: 20,
                                        ),
                                        title: 'remaining_days'.tr(),
                                        value: '$_remainingDaysAfterRequest',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () =>
                                            _showSelectedDatesListDialog(
                                              context,
                                            ),
                                        child: _buildTimeOffMetricCard(
                                          icon: const Icon(
                                            Icons.date_range,
                                            color: Color(0xFF004FDE),
                                            size: 20,
                                          ),
                                          title: 'selected_dates'.tr(),
                                          value: _selectedDatesSummary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFE8E8E8),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8F9FA),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFEEEEEE),
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.notes,
                                                color: Color(0xFF004FDE),
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'notes_label'.tr(),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w600,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _notesController.text.trim().isEmpty
                                            ? 'N/A'
                                            : _notesController.text,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
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
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'selected_days'.tr(),
            '$_selectedDaysCount',
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
                      // Inspecting a zero-balance type is allowed, but it must
                      // not be possible to assign or save against it.
                      _baseAvailableDaysForType(_timeOffType) <= 0 ||
                      (_editingId == null && _selectedDates.isEmpty) ||
                      (_editingId != null && !_hasUnsavedChanges) ||
                      _requestedDaysExceedAvailable)
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
              child: Text(
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
                  // Every type stays selectable so HR can inspect the
                  // worker's existing dates for a type even when its balance
                  // is zero (the calendar only shows dates for the selected
                  // type). Zero-balance types are styled grey as a hint;
                  // adding new dates and saving are blocked separately.
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
                  setState(() {
                    _timeOffType = v;
                    _hasTypeChanged = true;
                    // Keep the edit context and selected dates. The save
                    // transaction restores the original type's balance before
                    // deducting these dates from the newly selected type.
                    _syncSelectionBounds();
                  });
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
              if (dx > 5 || dy > 5) _dragMoved = true;
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
            for (final date in TimeOffService.inclusiveDateRange(
              anchor,
              current,
            )) {
              if (_isNonWorkingDate(date)) continue;
              if (isDragRemoving) {
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
              _toggleDate(_dragAnchorDate!);
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
    const headerHeight = 77.0;
    const calendarPadding = 16.0;
    final adjustedDy = position.dy - headerHeight - calendarPadding;
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

  void _toggleDate(DateTime date) {
    final selectedDate = _dateOnly(date);
    final isRemoving = _selectedDates.contains(selectedDate);
    if (!isRemoving && _isNonWorkingDate(selectedDate)) {
      FlashySnackBar.show(
        context,
        message: 'time_off_non_working_day_blocked'.tr(),
        isError: true,
      );
      return;
    }

    if (!isRemoving && _selectedWorker != null) {
      final savedLeave = TimeOffService.activeLeaveForWorker(
        _selectedWorker!,
        _timeoffRecords,
        onDate: selectedDate,
        excludingRecordId: _editingId,
      );
      if (savedLeave != null) {
        // Date already has an assigned leave — keep it locked.
        FlashySnackBar.show(
          context,
          message: 'date_already_has_leave'.tr(),
          isError: true,
        );
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
    final savedColor = savedType != null
        ? LeaveColors.getColor(savedType)
        : null;

    final selectedColor = LeaveColors.getColor(_timeOffType);
    final bgColor = isSelected
        ? selectedColor
        : (savedColor ??
              (isDisabled ? const Color(0xFFF1F5F9) : Colors.transparent));

    final borderColor = isSelected
        ? selectedColor
        : (savedColor ?? Colors.grey.shade300);

    final textColor = isDisabled && savedColor == null
        ? const Color(0xFFB0B7C3)
        : (isSelected || savedColor != null
              ? const Color(0xFFFFFFFF)
              : Colors.black);

    // Every date cell previews the currently selected dropdown type. Dates
    // already saved in Firebase keep their persisted leave type instead.
    final tooltipType = savedType ?? _timeOffType;
    final tooltipOption = _leaveTypeOptions
        .cast<Map<String, String>?>()
        .firstWhere(
          (option) => option?['value'] == tooltipType,
          orElse: () => null,
        );
    final tooltipTypeLabel = tooltipOption?['labelKey']?.tr() ?? tooltipType;
    // Match the Selected Dates summary (_formatDate -> dd/MM/yyyy). The generic
    // localized yMd pattern resolves to US M/d/yyyy for the default 'en' locale,
    // which would render 11 Aug as 8/11/2026 and mismatch the rest of the screen.
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
    );
  }

  Widget _buildNotesAndSummary() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isNarrow = constraints.maxWidth < 700;

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
                readOnly: widget.viewOnly,
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
              '$_requestedDays',
              Colors.black,
            ),
            _buildSummaryRow(
              'remaining_days'.tr(),
              '$_remainingDaysAfterRequest',
              _remainingDaysAfterRequest >= 0 ? Colors.black : Colors.red,
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [notesWidget, const SizedBox(height: 24), summaryWidget],
          );
        }

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
      },
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
    if (_editingId != null && !_hasUnsavedChanges) return;

    if (_editingRecord != null &&
        !TimeOffService.isEditableRecord(_editingRecord!)) {
      FlashySnackBar.show(
        context,
        message: 'past_time_off_edit_blocked'.tr(),
        isError: true,
      );
      return;
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
          if (!TimeOffService.isEditableRecord(oldRecord)) {
            throw const PastTimeOffEditException();
          }
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

  void _showAddAnnualLeavesDialog() {
    final TextEditingController amountController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            'add_leaves_title'.tr(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFamily: 'SF Pro Display',
            ),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'enter_leaves_to_add'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'SF Pro Display'),
                  decoration: InputDecoration(
                    hintText: 'e.g. 5',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'please_enter_amount'.tr();
                    }
                    final parsed = int.tryParse(val.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'invalid_number'.tr();
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'cancel'.tr(),
                style: const TextStyle(
                  color: Colors.grey,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0247C4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final addedAmount = int.parse(amountController.text.trim());
                  Navigator.of(ctx).pop();
                  await _addAnnualLeaves(addedAmount);
                }
              },
              child: Text(
                'add_btn'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addAnnualLeaves(int amount) async {
    if (_selectedWorker == null) return;
    setState(() => _isLoading = true);

    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      final workerId =
          (_selectedWorker!['workerId'] ?? _selectedWorker!['id'] ?? '')
              .toString();
      final currentAnnual = TimeOffService.configuredPaidLeaveAllowance(
        _selectedWorker!,
      );
      final currentAvailable = isGuest
          ? int.tryParse(
                  _selectedWorker!['availableAnnualLeaves']?.toString() ?? '0',
                ) ??
                0
          : _availableDays;
      final newAnnual = currentAnnual + amount;
      final newAvailable = currentAvailable + amount;

      if (isGuest) {
        final workerIdx = DummyData.workers.indexWhere((worker) {
          final workerId = (worker['id'] ?? '').toString().trim();
          final selectedId =
              (_selectedWorker!['workerId'] ?? _selectedWorker!['id'] ?? '')
                  .toString()
                  .trim();
          if (workerId.isNotEmpty && selectedId.isNotEmpty) {
            return workerId == selectedId;
          }
          return (worker['email'] ?? '').toString().trim().toLowerCase() ==
              (_selectedWorker!['email'] ?? '').toString().trim().toLowerCase();
        });
        if (workerIdx != -1) {
          DummyData.workers[workerIdx]['annualLeaves'] = newAnnual;
          DummyData.workers[workerIdx]['availableAnnualLeaves'] = newAvailable;
          DummyData.workers[workerIdx].addAll(
            TimeOffService.canonicalWorkerLeaveFields(
              DummyData.workers[workerIdx],
            ),
          );
          await DummyData.saveToPrefs();

          setState(() {
            _selectedWorker = Map<String, dynamic>.from(
              DummyData.workers[workerIdx],
            );
          });
        }
      } else {
        if (workerId.isEmpty) {
          throw StateError('Missing worker id');
        }
        await _firestore.updateWorkerLeaves(workerId, {
          'annualLeaves': newAnnual,
          'availableAnnualLeaves': newAvailable,
        });

        setState(() {
          final updatedWorker = <String, dynamic>{
            ..._selectedWorker!,
            'annualLeaves': newAnnual,
            'availableAnnualLeaves': newAvailable,
          };
          _selectedWorker = {
            ...updatedWorker,
            ...TimeOffService.canonicalWorkerLeaveFields(updatedWorker),
          };
        });
      }

      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'add_leaves_success'.tr(
            namedArgs: {'count': amount.toString()},
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'add_leaves_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildTimeOffMetricCard({
    required Widget icon,
    required String title,
    required String value,
  }) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEEEEEE)),
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
                    color: Color(0xFF64748B),
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
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
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
    );
  }

  void _showSelectedDatesListDialog(BuildContext context) {
    final String dayDisplayType = _localizedSelectedLeaveType;
    final localeName = context.locale.toString();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 560,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(ctx).width * 0.92,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
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
                          namedArgs: {
                            'count': '${_sortedSelectedDates.length}',
                          },
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
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _sortedSelectedDates.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'no_dates_selected'.tr(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _sortedSelectedDates.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: Color(0xFFEEEEEE),
                          ),
                          itemBuilder: (context, index) {
                            final date = _sortedSelectedDates[index];
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
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: LeaveColors.getBgColor(
                                          _timeOffType,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        dayDisplayType,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: LeaveColors.getColor(
                                            _timeOffType,
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
              Container(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0247C4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'close'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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
  }
}
