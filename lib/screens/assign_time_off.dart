import 'dart:async';
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

import 'package:easy_localization/easy_localization.dart';
import '../widgets/notification_bell.dart';

class AssignTimeOffScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;
  final Map<String, dynamic>? initialWorker;
  const AssignTimeOffScreen({
    super.key,
    required this.onBack,
    this.onProfileTap,
    this.onNotificationTap,
    this.initialWorker,
  });

  @override
  State<AssignTimeOffScreen> createState() => _AssignTimeOffScreenState();
}

class _AssignTimeOffScreenState extends State<AssignTimeOffScreen> {
  static const List<Map<String, String>> _leaveTypeOptions = [
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

  late AuthService _authService;
  late FirestoreService _firestore;
  bool _isLoading = false;
  String _timeOffType = 'Sick Leave';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  DateTime _calendarMonth = DateTime.now();
  DateTime _calendarMonth2 = DateTime.now();
  Set<DateTime> _selectedDates = <DateTime>{};
  DateTime? _dragAnchorDate;
  DateTime? _lastDragDate;
  Set<DateTime> _selectionBeforeDrag = <DateTime>{};
  bool _dragExceededAvailableDays = false;

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

  @override
  void initState() {
    super.initState();
    if (widget.initialWorker != null) {
      _selectedWorker = widget.initialWorker;
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
    if (_selectedWorker != null &&
        _selectedWorker!['action'] != null &&
        _selectedWorker!['action'].toString().isNotEmpty) {
      _editingId = _selectedWorker!['id']?.toString();
      _timeOffType = _selectedWorker!['action'].toString();
      _selectedDates = TimeOffService.selectedDatesForRecord(
        _selectedWorker!,
      ).toSet();
      _syncSelectionBounds();
      _notesController.text = _selectedWorker!['notes']?.toString() ?? '';
    } else {
      _editingId = null;
      _selectedDates = <DateTime>{};
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _timeOffType = 'Sick Leave';
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
      _timeOffType = 'Sick Leave';
    }
    _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);

    _calendarMonth2 = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + 1,
      1,
    );
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

  void _loadTimeoffForSelectedWorker() {
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
      if (mounted) setState(() => _timeoffRecords = records);
      return;
    }
    _firestore
        .getTimeoffForWorker(workerId)
        .then((snapshot) {
          if (!mounted) return;
          setState(() {
            _timeoffRecords = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
          });
        })
        .catchError((_) {});
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

  bool get _requestedDaysExceedAvailable =>
      _usesPaidAllowance && _selectedDaysCount > _availableDays;

  int get _requestedDays =>
      _requestedDaysExceedAvailable ? 0 : _selectedDaysCount;

  int get _remainingDaysAfterRequest {
    if (!_isGuest && !_isPaidLeave) return _availableDays;
    return _availableDays - _requestedDays;
  }

  String get _selectedDatesSummary {
    final dates = _sortedSelectedDates;
    if (dates.isEmpty) return 'select_date'.tr();
    final visibleDates = dates.take(3).map(_formatDate).join(', ');
    final remaining = dates.length - 3;
    return remaining > 0 ? '$visibleDates +$remaining' : visibleDates;
  }

  int get _availableDays {
    if (_selectedWorker == null) return 0;
    if (_isGuest) {
      return TimeOffService.remainingPaidLeave(
        _selectedWorker!,
        _timeoffRecords,
        excludingRecordId: _editingId,
      );
    }

    final worker = _selectedWorkerForService;
    final total = TimeOffService.configuredPaidLeaveAllowance(worker);
    final used = TimeOffService.paidDaysUsedForWorker(
      worker,
      _timeoffRecords,
      excludingRecordId: _editingId,
    );
    return (total - used).clamp(0, total);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _workersSub?.cancel();
    _holidaysSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 24),
                  _buildMainCard(),
                ],
              ),
            ),
          ),
        ],
      ),
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
            onTap: widget.onBack,
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

    final bool isExhausted =
        _selectedWorker != null &&
        _editingId == null &&
        _availableDays <= 0 &&
        (_isGuest || _isPaidLeave);

    if (isExhausted) {
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
                Icons.event_busy_rounded,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'all_leaves_utilized'.tr(),
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
              'paid_leave_exhausted_help'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontFamily: 'SF Pro Display',
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0247C4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  elevation: 0,
                ),
                onPressed: () => _showAddAnnualLeavesDialog(),
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: Text(
                  'add_more_annual_leaves'.tr(),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
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
          _buildUnifiedDaysGrid(),
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
                  'tap_dates_to_select'.tr(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              if (_selectedDates.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedDates.clear();
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
        if (_editingId != null) ...[
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: _isLoading ? null : _handleCancelTimeOff,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFE53935),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'cancel_time_off'.tr(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
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
              onPressed: (_selectedWorker == null || _isLoading)
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
                items: _leaveTypeOptions.map((option) {
                  final label = option['labelKey']!.tr();
                  final remaining = _availableDays;
                  final displayText = _selectedWorker != null
                      ? '$label – $remaining ${'remaining_days'.tr()}'
                      : label;
                  return DropdownMenuItem<String>(
                    value: option['value'],
                    child: Text(
                      displayText,
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _timeOffType = v;
                    });
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabeledInput(String label, String value) {
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
        ),
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
        constraints: const BoxConstraints(maxWidth: 374),
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
                      setState(() {
                        _calendarMonth = newMonth;
                      });
                    } else {
                      final newMonth = DateTime(
                        _calendarMonth2.year,
                        _calendarMonth2.month - 1,
                        1,
                      );
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
                      setState(() {
                        _calendarMonth = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month + 1,
                          1,
                        );
                      });
                    } else {
                      setState(() {
                        _calendarMonth2 = DateTime(
                          _calendarMonth2.year,
                          _calendarMonth2.month + 1,
                          1,
                        );
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
        _buildWeekday('weekday_sun'.tr(), const Color(0xFFFF0004)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_mon'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_tue'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_wed'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_thu'.tr(), const Color(0xFF0247C4)),
        const SizedBox(width: 4),
        _buildWeekday('weekday_fri'.tr(), const Color(0xFF4AC000)),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanDown: (details) {
        final pos = details.localPosition;
        final isSecond = pos.dx > calendarWidth + 24;
        final monthDate = isSecond ? _calendarMonth2 : _calendarMonth;
        _dragAnchorDate = _dateAtGridPosition(monthDate, details.localPosition);
        _lastDragDate = null;
        _selectionBeforeDrag = Set<DateTime>.from(_selectedDates);
        _dragExceededAvailableDays = false;
      },
      onPanUpdate: (details) {
        final anchor = _dragAnchorDate;
        final pos = details.localPosition;
        final isSecond = pos.dx > calendarWidth + 24;
        final monthDate = isSecond ? _calendarMonth2 : _calendarMonth;
        final current = _dateAtGridPosition(monthDate, details.localPosition);
        if (anchor == null || current == null || current == _lastDragDate) {
          return;
        }
        _lastDragDate = current;

        final candidate = Set<DateTime>.from(_selectionBeforeDrag);
        var exceededAvailableDays = false;
        for (final date in TimeOffService.inclusiveDateRange(anchor, current)) {
          if (candidate.contains(date)) continue;
          if (_isNonWorkingDate(date)) continue;
          if (_usesPaidAllowance && candidate.length >= _availableDays) {
            if (!_isGuest) exceededAvailableDays = true;
            break;
          }
          candidate.add(date);
        }

        setState(() {
          _selectedDates = candidate;
          _dragExceededAvailableDays = exceededAvailableDays;
          _syncSelectionBounds();
        });
      },
      onPanEnd: (_) => _finishDateDrag(),
      onPanCancel: _finishDateDrag,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCalendar(_calendarMonth, isStartCalendar: true),
          const SizedBox(width: 24),
          _buildCalendar(_calendarMonth2, isStartCalendar: false),
        ],
      ),
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
    final column = (position.dx / cellExtent).floor();
    final row = (position.dy / cellExtent).floor();
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
        message: 'requested_leaves_exceed_available'.tr(),
        isError: true,
      );
    }
    _dragAnchorDate = null;
    _lastDragDate = null;
    _selectionBeforeDrag = <DateTime>{};
    _dragExceededAvailableDays = false;
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
    if (!isRemoving &&
        _usesPaidAllowance &&
        _selectedDates.length >= _availableDays) {
      FlashySnackBar.show(
        context,
        message: 'requested_leaves_exceed_available'.tr(),
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
    final isSunday = date?.weekday == 7;
    final isFriday = date?.weekday == 5;
    final dayColor = isSunday
        ? const Color(0xFFFF0004)
        : (isFriday ? const Color(0xFF4AC000) : Colors.black);
    final selectedBg = isFriday
        ? const Color(0xFF4AC000)
        : const Color(0xFFFF0004);
    final selectedBorder = isFriday
        ? const Color(0xFF4AC000)
        : const Color(0xFFFF0004);
    return Center(
      child: SizedBox(
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: date == null || isDisabled ? null : () => _toggleDate(date),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? selectedBg
                  : (isDisabled ? const Color(0xFFF1F5F9) : Colors.transparent),
              border: Border.all(
                color: isSelected
                    ? selectedBorder
                    : (isSunday
                          ? const Color(0xFFFF0004).withValues(alpha: 0.4)
                          : (isFriday
                                ? const Color(0xFF4AC000).withValues(alpha: 0.4)
                                : Colors.grey.shade300)),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              day,
              style: TextStyle(
                color: isDisabled
                    ? const Color(0xFFB0B7C3)
                    : (isSelected ? const Color(0xFFFFFFFF) : dayColor),
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
              'available_annual_leave'.tr(),
              '$_availableDays',
              _availableDays > 0 ? Colors.black : Colors.red,
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
    if (_isLoading) return;

    if (_selectedWorker == null &&
        _notesController.text.trim().isEmpty &&
        _selectedDates.isEmpty) {
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

    // Hard eligibility validation: never rely only on UI filtering. A stale
    // or supplied worker object must be rejected if the worker is
    // inactive/terminated/deleted/archived.
    if (!_isEligibleWorker(_selectedWorker!)) {
      FlashySnackBar.show(
        context,
        message: 'guest_action_not_allowed'.tr(),
        isError: true,
      );
      return;
    }

    if (_notesController.text.trim().isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_notes'.tr(),
        isError: true,
      );
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
        message: 'requested_leaves_exceed_available'.tr(),
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
        // Date-only values: never use .toUtc() on business date fields. In
        // Pakistan (+05:00) a selected 03 Aug 00:00 local would otherwise be
        // saved as 02 Aug 19:00Z, shifting the leave to the wrong day.
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

      final projectedRecords =
          _timeoffRecords
              .where((record) => record['id']?.toString() != _editingId)
              .map(Map<String, dynamic>.from)
              .toList()
            ..add({...recordMap, 'id': _editingId ?? 'pending_time_off'});
      final serviceWorker = _selectedWorkerForService;
      final usedLeaveDays = isGuest
          ? TimeOffService.leaveDaysUsedForWorker(
              _selectedWorker!,
              projectedRecords,
            )
          : TimeOffService.paidDaysUsedForWorker(
              serviceWorker,
              projectedRecords,
            );
      final totalPaidDays = TimeOffService.configuredPaidLeaveAllowance(
        isGuest ? _selectedWorker! : serviceWorker,
      );
      final remainingPaidDays = (totalPaidDays - usedLeaveDays).clamp(
        0,
        totalPaidDays,
      );
      final balanceUpdate = <String, dynamic>{
        'availableAnnualLeaves': remainingPaidDays.toString(),
        'leavesUsed': usedLeaveDays.toString(),
      };

      if (isGuest) {
        if (_editingId != null) {
          final idx = DummyData.timeoff.indexWhere(
            (t) => t['id'] == _editingId,
          );
          if (idx != -1) {
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
          DummyData.workers[workerIdx].addAll(balanceUpdate);
        }
        await DummyData.saveToPrefs();
      } else {
        await _firestore.saveTimeOffWithWorkerBalance(
          timeOffId: _editingId,
          record: recordMap,
          workerId: workerId,
          balance: balanceUpdate,
        );
      }

      if (mounted) {
        FlashySnackBar.show(
          context,
          message:
              (_editingId == null
                      ? 'assign_time_off_success'
                      : 'update_time_off_success')
                  .tr(),
        );
        widget.onBack();
        return;
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

  Future<void> _handleCancelTimeOff() async {
    if (_isLoading || _editingId == null || _selectedWorker == null) return;

    setState(() => _isLoading = true);
    try {
      final cancelledRecordId = _editingId!;
      final projectedRecords = _timeoffRecords.map((record) {
        if (record['id']?.toString() != cancelledRecordId) {
          return Map<String, dynamic>.from(record);
        }
        return {
          ...record,
          'status': 'Cancelled',
          'cancelledAt': DateTime.now(),
        };
      }).toList();
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      final serviceWorker = _selectedWorkerForService;
      final usedLeaveDays = isGuest
          ? TimeOffService.leaveDaysUsedForWorker(
              _selectedWorker!,
              projectedRecords,
            )
          : TimeOffService.paidDaysUsedForWorker(
              serviceWorker,
              projectedRecords,
            );
      final totalPaidDays = TimeOffService.configuredPaidLeaveAllowance(
        isGuest ? _selectedWorker! : serviceWorker,
      );
      final balanceUpdate = <String, dynamic>{
        'availableAnnualLeaves': (totalPaidDays - usedLeaveDays)
            .clamp(0, totalPaidDays)
            .toString(),
        'leavesUsed': usedLeaveDays.toString(),
      };

      final workerId =
          (_selectedWorker!['workerId'] ?? _selectedWorker!['id'] ?? '')
              .toString()
              .trim();
      if (isGuest) {
        final recordIndex = DummyData.timeoff.indexWhere(
          (record) => record['id']?.toString() == cancelledRecordId,
        );
        if (recordIndex != -1) {
          DummyData.timeoff[recordIndex] = {
            ...DummyData.timeoff[recordIndex],
            'status': 'Cancelled',
            'cancelledAt': DateTime.now(),
          };
        }
        final workerIndex = DummyData.workers.indexWhere((worker) {
          final id = (worker['id'] ?? '').toString().trim();
          if (workerId.isNotEmpty && id.isNotEmpty) return workerId == id;
          return (worker['email'] ?? '').toString().trim().toLowerCase() ==
              (_selectedWorker!['email'] ?? '').toString().trim().toLowerCase();
        });
        if (workerIndex != -1) {
          DummyData.workers[workerIndex].addAll(balanceUpdate);
        }
        await DummyData.saveToPrefs();
      } else {
        if (workerId.isEmpty) {
          throw StateError('Missing worker id');
        }
        await _firestore.cancelTimeOffWithWorkerBalance(
          timeOffId: cancelledRecordId,
          workerId: workerId,
          balance: balanceUpdate,
        );
      }

      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'time_off_cancelled_for_worker'.tr(
          namedArgs: {
            'name': (_selectedWorker!['name'] ?? 'worker_fallback'.tr())
                .toString(),
          },
        ),
      );
      widget.onBack();
      return;
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'time_off_cancel_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      final currentAnnual =
          int.tryParse(_selectedWorker!['annualLeaves']?.toString() ?? '12') ??
          12;
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
          DummyData.workers[workerIdx]['annualLeaves'] = newAnnual.toString();
          DummyData.workers[workerIdx]['availableAnnualLeaves'] = newAvailable
              .toString();
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
          'annualLeaves': newAnnual.toString(),
          'availableAnnualLeaves': newAvailable.toString(),
        });

        setState(() {
          _selectedWorker = {
            ..._selectedWorker!,
            'annualLeaves': newAnnual.toString(),
            'availableAnnualLeaves': newAvailable.toString(),
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
}
