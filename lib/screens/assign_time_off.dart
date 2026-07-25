import 'dart:async';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/time_off_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/guest_restriction.dart';

import 'package:easy_localization/easy_localization.dart';
import '../widgets/notification_bell.dart';
import '../utils/leave_balance_helper.dart';

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
  final TextEditingController _notesController = TextEditingController();
  String? _editingId;

  List<Map<String, dynamic>> _workers = [];
  Map<String, dynamic>? _selectedWorker;
  StreamSubscription? _workersSub;
  List<Map<String, dynamic>> _timeoffRecords = [];
  StreamSubscription? _timeoffSub;

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    if (widget.initialWorker != null) {
      _selectedWorker = widget.initialWorker;
    }
    _resetFormFields();
    _loadWorkers();
  }

  @override
  void didUpdateWidget(covariant AssignTimeOffScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialWorker != null &&
        widget.initialWorker!['email'] != oldWidget.initialWorker?['email']) {
      _selectedWorker = widget.initialWorker;
      _resetFormFields();
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
      _timeOffType = 'Annual Leave';
      _notesController.clear();
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
      setState(() {
        _workers = DummyData.workers;
        _timeoffRecords = DummyData.timeoff;
        if (widget.initialWorker != null) {
          final targetEmail = (widget.initialWorker!['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          _selectedWorker = _workers.firstWhere(
            (w) =>
                (w['email'] ?? '').toString().trim().toLowerCase() ==
                targetEmail,
            orElse: () => widget.initialWorker!,
          );
        } else if (_workers.isNotEmpty) {
          if (_selectedWorker == null) {
            _selectedWorker = _workers.first;
          } else {
            final targetEmail = (_selectedWorker!['email'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            _selectedWorker = _workers.firstWhere(
              (w) =>
                  (w['email'] ?? '').toString().trim().toLowerCase() ==
                  targetEmail,
              orElse: () => _workers.first,
            );
          }
        } else {
          _selectedWorker = null;
        }
      });
    } else {
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _workers = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              if (widget.initialWorker != null) {
                final targetEmail = (widget.initialWorker!['email'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                _selectedWorker = _workers.firstWhere(
                  (w) =>
                      (w['email'] ?? '').toString().trim().toLowerCase() ==
                      targetEmail,
                  orElse: () => widget.initialWorker!,
                );
              } else if (_workers.isNotEmpty) {
                if (_selectedWorker == null) {
                  _selectedWorker = _workers.first;
                } else {
                  final targetEmail = (_selectedWorker!['email'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
                  _selectedWorker = _workers.firstWhere(
                    (w) =>
                        (w['email'] ?? '').toString().trim().toLowerCase() ==
                        targetEmail,
                    orElse: () => _workers.first,
                  );
                }
              } else {
                _selectedWorker = null;
              }
            });
          }
        },
        onError: (e) {

        },
      );
      _timeoffSub = _firestore.timeoffStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _timeoffRecords = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
            });
          }
        },
        onError: (e) {

        },
      );
    }
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

  int get _selectedDaysCount => _selectedDates.length;

  bool get _requestedDaysExceedAvailable => _selectedDaysCount > _availableDays;



  int get _requestedDays =>
      _requestedDaysExceedAvailable ? 0 : _selectedDaysCount;

  String get _selectedDatesSummary {
    final dates = _sortedSelectedDates;
    if (dates.isEmpty) return 'select_date'.tr();
    final visibleDates = dates.take(3).map(_formatDate).join(', ');
    final remaining = dates.length - 3;
    return remaining > 0 ? '$visibleDates +$remaining' : visibleDates;
  }

  int get _alreadyUsedDays {
    if (_selectedWorker == null) return 0;
    final workerEmail = (_selectedWorker!['email'] ?? '')
        .toString()
        .toLowerCase();
    String typeKey;
    switch (_timeOffType) {
      case 'Annual Leave':
        typeKey = 'Annual Leave';
      case 'Sick Leave':
        typeKey = 'Sick Leave';
      case 'Casual Leave':
        typeKey = 'Casual Leave';
      case 'Medical Leave':
        typeKey = 'Medical Leave';
      case 'Custom Leave':
        typeKey = 'Custom Leave';
      default:
        return 0;
    }
    int used = 0;
    for (final record in _timeoffRecords) {
      if (_editingId != null && record['id']?.toString() == _editingId) {
        continue;
      }
      final recordEmail = (record['email'] ?? '').toString().toLowerCase();
      if (recordEmail != workerEmail) continue;
      final action = (record['action'] ?? record['type'] ?? '').toString();
      if (action != typeKey) continue;
      final requestedDays = record['requestedDays'];
      if (requestedDays is int) {
        used += requestedDays;
      }
    }
    return used;
  }

  int get _availableDays {
    if (_selectedWorker == null) return 0;
    if (_timeOffType == 'Custom Leave') return 999;

    final String? availKey;
    final String configKey;

    switch (_timeOffType) {
      case 'Annual Leave':
        availKey = 'availableAnnualLeaves';
        configKey = 'annualLeaves';
      case 'Sick Leave':
        availKey = 'availableSickLeaves';
        configKey = 'sickLeaves';
      case 'Casual Leave':
        availKey = 'availableCasualLeaves';
        configKey = 'casualLeaves';
      case 'Medical Leave':
        availKey = 'availableMedicalLeaves';
        configKey = 'medicalLeaves';
      default:
        return 0;
    }

    if (availKey != null) {
      final raw = (_selectedWorker![availKey] ?? '').toString();
      if (raw.isNotEmpty) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return parsed < 0 ? 0 : parsed;
      }
    }

    String raw = (_selectedWorker![configKey] ?? '').toString();

    if (raw.isEmpty) {

      final aliases = switch (_timeOffType) {
        'Annual Leave' => const [
          'annual_leave',
          'annualLeave',
          'annual_leave_days',
          'annualLeaves',
        ],
        'Sick Leave' => const [
          'sick_leave',
          'sickLeave',
          'sick_leave_days',
          'sickLeaves',
        ],
        'Casual Leave' => const [
          'casual_leave',
          'casualLeave',
          'casual_leave_days',
          'casualLeaves',
        ],
        _ => const [],
      };

      for (final a in aliases) {
        final v = _selectedWorker![a];
        if (v != null && v.toString().trim().isNotEmpty) {
          raw = v.toString();
          break;
        }
      }
    }

    final total = int.tryParse(raw);
    if (total == null) return 0;

    final used = _alreadyUsedDays;
    final remaining = total - used;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _workersSub?.cancel();
    _timeoffSub?.cancel();
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
    final bool isExhausted =
        _selectedWorker != null &&
        LeaveBalanceHelper.shouldBlockTimeOffForm(
          _selectedWorker!,
          isEditing: _editingId != null,
        );

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
              'Please add more leaves to assign a new time off request for this worker.',
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
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              _buildCalendar(_calendarMonth, isStartCalendar: true),
              _buildCalendar(_calendarMonth2, isStartCalendar: false),
            ],
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
                      final isGuest = _authService.currentUser?.isAnonymous ?? false;
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
                items: [
                  DropdownMenuItem(
                    value: 'Annual Leave',
                    child: Text(
                      'annual_leave'.tr(),
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Sick Leave',
                    child: Text(
                      'sick_leave_type'.tr(),
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Casual Leave',
                    child: Text(
                      'casual_leave_type'.tr(),
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Medical Leave',
                    child: Text(
                      'medical_leave_type'.tr(),
                      style: const TextStyle(
                        fontFamily: 'SF Pro Display',
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
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
                    final currentMonth = DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      1,
                    );
                    if (isStartCalendar) {
                      final newMonth = DateTime(
                        _calendarMonth.year,
                        _calendarMonth.month - 1,
                        1,
                      );
                      if (!newMonth.isBefore(currentMonth)) {
                        setState(() {
                          _calendarMonth = newMonth;
                        });
                      }
                    } else {
                      final newMonth = DateTime(
                        _calendarMonth2.year,
                        _calendarMonth2.month - 1,
                        1,
                      );
                      if (!newMonth.isBefore(currentMonth)) {
                        setState(() {
                          _calendarMonth2 = newMonth;
                        });
                      }
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanDown: (details) {
        _dragAnchorDate = _dateAtGridPosition(monthDate, details.localPosition);
        _lastDragDate = null;
        _selectionBeforeDrag = Set<DateTime>.from(_selectedDates);
        _dragExceededAvailableDays = false;
      },
      onPanUpdate: (details) {
        final anchor = _dragAnchorDate;
        final current = _dateAtGridPosition(monthDate, details.localPosition);
        if (anchor == null || current == null || current == _lastDragDate) {
          return;
        }
        _lastDragDate = current;

        final candidate = Set<DateTime>.from(_selectionBeforeDrag);
        var exceededAvailableDays = false;
        for (final date in TimeOffService.inclusiveDateRange(anchor, current)) {
          if (candidate.contains(date)) continue;
          if (candidate.length >= _availableDays) {
            exceededAvailableDays = true;
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
      child: Column(children: rows),
    );
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
    if (!isRemoving && _selectedDates.length >= _availableDays) {
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

  Widget _buildDayCell(String day, {bool isSelected = false, DateTime? date}) {
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
          onTap: date == null ? null : () => _toggleDate(date),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
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
                color: isSelected ? const Color(0xFFFFFFFF) : dayColor,
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
              _timeOffType == 'Sick Leave'
                  ? 'available_sick_leave'.tr()
                  : _timeOffType == 'Casual Leave'
                  ? 'available_casual_leave'.tr()
                  : 'available_annual_leave'.tr(),
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
              '${_availableDays - _requestedDays}',
              _availableDays - _requestedDays >= 0 ? Colors.black : Colors.red,
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

  Future<void> _handleSave() async {
    if (_isLoading) return;
    if (_selectedWorker == null) {
      FlashySnackBar.show(
        context,
        message: 'please_select_worker_first'.tr(),
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

    if (_requestedDaysExceedAvailable) {
      FlashySnackBar.show(
        context,
        message: 'requested_leaves_exceed_available'.tr(),
        isError: true,
      );
      return;
    }




    final availableDaysBeforeSave = _availableDays;
    final usedDaysBeforeSave = _alreadyUsedDays;
    final requestedDaysAtSave = _requestedDays;

    setState(() => _isLoading = true);

    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      final recordMap = {
        'name': _selectedWorker!['name'] ?? 'Worker',
        'email': _selectedWorker!['email'] ?? '',
        'position': _selectedWorker!['position'] ?? 'Worker',
        'contact': _getWorkerPhone(_selectedWorker!),
        'action': _timeOffType,
        'type': _timeOffType,
        'startDate': _startDate,
        'endDate': _endDate,
        'selectedDates': _sortedSelectedDates.toList(),
        'notes': _notesController.text.trim(),
        'requestedDays': _requestedDays,
        'status': 'Approved',
        'workerName': _selectedWorker!['name'] ?? 'Worker',
        'workerAvatar': _selectedWorker!['profileImage'] ?? '',
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
        await DummyData.saveToPrefs();
      } else {
        if (_editingId != null) {
          await _firestore.updateTimeOffRecord(_editingId!, recordMap);
        } else {
          await _firestore.addTimeOffRecord(recordMap);
        }
      }


      if (mounted) {
        final updatedBalance = LeaveBalanceHelper.balanceAfterRequest(
          availableBeforeSave: availableDaysBeforeSave,
          usedBeforeSave: usedDaysBeforeSave,
          requestedDays: requestedDaysAtSave,
        );
        final remainingLeaves = updatedBalance.remaining;
        final Map<String, dynamic> payrollUpdate = {};

        if (_timeOffType == 'Annual Leave') {
          payrollUpdate['availableAnnualLeaves'] = remainingLeaves.toString();
          payrollUpdate['leavesUsed'] = updatedBalance.used.toString();
        } else if (_timeOffType == 'Sick Leave') {
          payrollUpdate['availableSickLeaves'] = remainingLeaves.toString();
        } else if (_timeOffType == 'Casual Leave') {
          payrollUpdate['availableCasualLeaves'] = remainingLeaves.toString();
        }

        if (isGuest) {

          final workerIdx = DummyData.workers.indexWhere(
            (w) => w['email'] == _selectedWorker!['email'],
          );
          if (workerIdx != -1) {
            if (_timeOffType == 'Annual Leave') {
              DummyData.workers[workerIdx]['availableAnnualLeaves'] =
                  remainingLeaves.toString();
              DummyData.workers[workerIdx]['leavesUsed'] = updatedBalance.used
                  .toString();
            } else if (_timeOffType == 'Sick Leave') {
              DummyData.workers[workerIdx]['availableSickLeaves'] =
                  remainingLeaves.toString();
            } else if (_timeOffType == 'Casual Leave') {
              DummyData.workers[workerIdx]['availableCasualLeaves'] =
                  remainingLeaves.toString();
            }
            await DummyData.saveToPrefs();
          }
        } else {

          final workerId = (_selectedWorker!['id'] ?? '').toString();
          if (workerId.isNotEmpty && payrollUpdate.isNotEmpty) {
            await _firestore.updateWorkerLeaves(
              workerId,
              payrollUpdate,
            );
          }
        }
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
      final workerId = (_selectedWorker!['id'] ?? '').toString();
      final currentAnnual =
          int.tryParse(_selectedWorker!['annualLeaves']?.toString() ?? '12') ??
          12;
      final currentAvailable =
          int.tryParse(
            _selectedWorker!['availableAnnualLeaves']?.toString() ?? '0',
          ) ??
          0;
      final newAnnual = currentAnnual + amount;
      final newAvailable = currentAvailable + amount;

      if (isGuest) {
        final workerIdx = DummyData.workers.indexWhere(
          (w) => w['email'] == _selectedWorker!['email'],
        );
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
        if (workerId.isNotEmpty) {
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
