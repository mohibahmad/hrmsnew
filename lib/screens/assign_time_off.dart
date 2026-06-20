import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter/cupertino.dart' hide GestureDetector;
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/snackbar_utils.dart';
import '../utils/logout_dialog.dart';
import 'package:easy_localization/easy_localization.dart';

class AssignTimeOffScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onNotificationTap;
  final Map<String, dynamic>? initialWorker;
  const AssignTimeOffScreen({
    super.key,
    required this.onBack,
    this.onNotificationTap,
    this.initialWorker,
  });

  @override
  State<AssignTimeOffScreen> createState() => _AssignTimeOffScreenState();
}

class _AssignTimeOffScreenState extends State<AssignTimeOffScreen> {
  bool _isLoading = false;
  String _timeOffType = 'Annual Leave';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 9));
  late DateTime _calendarMonth;
  final TextEditingController _notesController = TextEditingController();

  List<Map<String, dynamic>> _workers = [];
  Map<String, dynamic>? _selectedWorker;
  bool _loadingWorkers = true;
  StreamSubscription? _workersSub;

  @override
  void initState() {
    super.initState();
    _calendarMonth = DateTime(_startDate.year, _startDate.month, 1);
    _loadWorkers();
  }

  void _loadWorkers() {
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _workers = DummyData.workers;
        if (widget.initialWorker != null) {
          _selectedWorker = _workers.firstWhere(
            (w) => w['email'] == widget.initialWorker!['email'],
            orElse: () => widget.initialWorker!,
          );
        } else if (_workers.isNotEmpty) {
          _selectedWorker = _workers.first;
        }
        _loadingWorkers = false;
      });
    } else {
      _workersSub = FirestoreService().workersStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _workers = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              if (widget.initialWorker != null) {
                _selectedWorker = _workers.firstWhere(
                  (w) => w['email'] == widget.initialWorker!['email'],
                  orElse: () => widget.initialWorker!,
                );
              } else if (_workers.isNotEmpty) {
                if (_selectedWorker == null ||
                    !_workers.any(
                      (w) => w['email'] == _selectedWorker!['email'],
                    )) {
                  _selectedWorker = _workers.first;
                }
              } else {
                _selectedWorker = null;
              }
              _loadingWorkers = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _loadingWorkers = false;
            });
          }
        },
      );
    }
  }

  Widget _buildWorkerDropdown() {
    if (widget.initialWorker != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'select_worker'.tr() == 'select_worker'
                ? 'Select Worker'
                : 'select_worker'.tr(),
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
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_selectedWorker?['name'] ?? widget.initialWorker!['name'] ?? ''} (${_selectedWorker?['position'] ?? widget.initialWorker!['position'] ?? ''})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'select_worker'.tr() == 'select_worker'
              ? 'Select Worker'
              : 'select_worker'.tr(),
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
            child: DropdownButton<Map<String, dynamic>>(
              isExpanded: true,
              value: _selectedWorker,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
              hint: const Text('Select a worker'),
              items: _workers.map((worker) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: worker,
                  child: Text(
                    '${worker['name'] ?? ''} (${worker['position'] ?? ''})',
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedWorker = v;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // Helper to get month name
  String _getMonthName(int month) {
    return DateFormat(
      'MMMM',
      context.locale.toString(),
    ).format(DateTime(2024, month));
  }

  // Helper to format date as DD/MM/YYYY
  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final initialDate = isStartDate ? _startDate : _endDate;
    DateTime tempPickedDate = initialDate;

    await showDialog(
      context: context,
      builder: (BuildContext builder) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 320,
            height: 300,
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: Text(
                        'cancel'.tr(),
                        style: const TextStyle(color: Colors.red),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    CupertinoButton(
                      child: Text(
                        'done'.tr(),
                        style: const TextStyle(color: Color(0xFF0247C4)),
                      ),
                      onPressed: () {
                        setState(() {
                          if (isStartDate) {
                            _startDate = tempPickedDate;
                            if (_endDate.isBefore(_startDate)) {
                              _endDate = _startDate.add(
                                const Duration(days: 9),
                              );
                            }
                          } else {
                            _endDate = tempPickedDate;
                            if (_endDate.isBefore(_startDate)) {
                              _startDate = _endDate.subtract(
                                const Duration(days: 9),
                              );
                              if (_startDate.isBefore(DateTime(2020))) {
                                _startDate = DateTime(2020);
                              }
                            }
                          }
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: initialDate,
                    minimumDate: DateTime(2020),
                    maximumDate: DateTime(2030),
                    onDateTimeChanged: (DateTime newDate) {
                      tempPickedDate = newDate;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int get _requestedDays {
    return _endDate.difference(_startDate).inDays + 1;
  }

  int get _availableDays {
    if (_selectedWorker == null) return 0;
    switch (_timeOffType) {
      case 'Annual Leave':
        return int.tryParse(
              (_selectedWorker!['annualLeaves'] ?? '').toString(),
            ) ??
            0;
      case 'Sick Leave':
        return int.tryParse(
              (_selectedWorker!['sickLeaves'] ?? '').toString(),
            ) ??
            0;
      case 'Casual Leave':
        return int.tryParse(
              (_selectedWorker!['casualLeaves'] ?? '').toString(),
            ) ??
            0;
      default:
        return 0;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _workersSub?.cancel();
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
    final user = AuthService().currentUser;
    final name = user?.displayName ?? 'user'.tr();

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
          const SizedBox(width: 24),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                showLogoutDialog(context);
              }
            },
            offset: const Offset(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            color: Color(0xFFFFFFFF),
            elevation: 8,
            tooltip: '',
            child: SvgPicture.asset(
              'assets/app_icon.svg',
              width: 42,
              height: 42,
              fit: BoxFit.contain,
            ),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'logout'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= MAIN CONTENT =================

  Widget _buildMainCard() {
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
          if (_loadingWorkers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_workers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No workers found. Please add workers first.',
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else ...[
            _buildWorkerDropdown(),
            const SizedBox(height: 20),
          ],
          _buildTopForm(),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCalendar(_calendarMonth)),
              const SizedBox(width: 24),
              Expanded(
                child: _buildCalendar(
                  DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildNotesAndSummary(),
        ],
      ),
    );
  }

  // ==== FORM ROW ====

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
            'start_date'.tr(),
            _formatDate(_startDate),
            isStart: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'end_date'.tr(),
            _formatDate(_endDate),
            isStart: false,
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
                  : () => _handleSave(),
              child: Text(
                'assign'.tr(),
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
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
              items: [
                DropdownMenuItem(
                  value: 'Annual Leave',
                  child: Text('annual_leave'.tr()),
                ),
                DropdownMenuItem(
                  value: 'Sick Leave',
                  child: Text('sick_leave_type'.tr()),
                ),
                DropdownMenuItem(
                  value: 'Casual Leave',
                  child: Text('leaves_tab'.tr()),
                ),
                DropdownMenuItem(
                  value: 'Maternity Leave',
                  child: Text('maternity_leave'.tr()),
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
      ],
    );
  }

  Widget _buildLabeledInput(
    String label,
    String value, {
    required bool isStart,
  }) {
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
        GestureDetector(
          onTap: () => _selectDate(context, isStart),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==== CALENDARS ====

  Widget _buildCalendar(DateTime monthDate) {
    String monthYear = '${_getMonthName(monthDate.month)} ${monthDate.year}';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month - 1,
                      1,
                    );
                  });
                },
                child: const Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 32),
              Text(
                monthYear,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month + 1,
                      1,
                    );
                  });
                },
                child: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildWeekdayRow(),
          const SizedBox(height: 6),
          _buildDaysGrid(monthDate),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow() {
    return Row(
      children: [
        Expanded(child: _buildWeekday('weekday_sun'.tr(), Colors.red)),
        const SizedBox(width: 8),
        Expanded(
          child: _buildWeekday('weekday_mon'.tr(), const Color(0xFF0247C4)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildWeekday('weekday_tue'.tr(), const Color(0xFF0247C4)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildWeekday('weekday_wed'.tr(), const Color(0xFF0247C4)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildWeekday('weekday_thu'.tr(), const Color(0xFF0247C4)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildWeekday('weekday_fri'.tr(), const Color(0xFF4CAF50)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildWeekday('weekday_sat'.tr(), const Color(0xFF0247C4)),
        ),
      ],
    );
  }

  Widget _buildWeekday(String day, Color color) {
    String shortDay = day;
    if (shortDay.length > 3) shortDay = shortDay.substring(0, 3);

    return Container(
      height: 18,
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
          rowChildren.add(Expanded(child: _buildDayCell('')));
        } else if (currentDay <= daysInMonth) {
          DateTime cellDate = DateTime(
            monthDate.year,
            monthDate.month,
            currentDay,
          );

          DateTime startStart = DateTime(
            _startDate.year,
            _startDate.month,
            _startDate.day,
          );
          DateTime endStart = DateTime(
            _endDate.year,
            _endDate.month,
            _endDate.day,
          );

          bool isSelected =
              cellDate.isAtSameMomentAs(startStart) ||
              cellDate.isAtSameMomentAs(endStart);
          bool inRange =
              cellDate.isAfter(startStart) && cellDate.isBefore(endStart);

          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$currentDay',
                isSelected: isSelected,
                inRange: inRange,
                date: cellDate,
              ),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(Expanded(child: _buildDayCell('')));
        }
        if (j < 6)
          rowChildren.add(const SizedBox(width: 8)); // Space between cells
      }
      rows.add(Row(children: rowChildren));
      if (currentDay > daysInMonth) break;
      if (i < 5) rows.add(const SizedBox(height: 8)); // Space between rows
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(
    String day, {
    bool isSelected = false,
    bool inRange = false,
    DateTime? date,
  }) {
    if (day.isEmpty) return const SizedBox();
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: () {
          if (date != null) {
            setState(() {
              // Simple logic: if click is before start date, update start date
              // else update end date
              if (date.isBefore(_startDate)) {
                _startDate = date;
              } else {
                _endDate = date;
              }
            });
          }
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.red
                : (inRange
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.transparent),
            border: Border.all(
              color: isSelected
                  ? Colors.red
                  : (inRange
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.grey.shade300),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            day,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFFFFFFFF)
                  : (inRange ? Colors.red : Colors.black),
              fontSize: 13,
              fontWeight: isSelected || inRange
                  ? FontWeight.w600
                  : FontWeight.normal,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ),
    );
  }

  // ==== BOTTOM NOTES & SUMMARY ====

  Widget _buildNotesAndSummary() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 13,
          child: Column(
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
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: TextField(
                  controller: _notesController,
                  maxLines: null,
                  decoration: InputDecoration.collapsed(
                    hintText: 'please_enter_notes'.tr(),
                    hintStyle: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48),
        Expanded(
          flex: 10,
          child: Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Column(
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
                  '${_availableDays - _requestedDays}',
                  _availableDays - _requestedDays >= 0
                      ? Colors.black
                      : Colors.red,
                ),
              ],
            ),
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

  /// Robust helper: reads 'phone' or 'contact' from a worker map,
  /// falling through empty strings as well as nulls.
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
      FlashySnackBar.show(context, message: 'Please select a worker first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;
      final recordMap = {
        'name': _selectedWorker!['name'] ?? 'Worker',
        'email': _selectedWorker!['email'] ?? '',
        'position': _selectedWorker!['position'] ?? 'Worker',
        'contact': _getWorkerPhone(_selectedWorker!),
        'action': _timeOffType,
        'type': _timeOffType,
        'startDate':
            '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
        'endDate':
            '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
        'notes': _notesController.text,
        'requestedDays': _requestedDays,
        'status': 'Approved',
        'workerName': _selectedWorker!['name'] ?? 'Worker',
        'workerAvatar':
            _selectedWorker!['profileImage'] ?? 'assets/profileimage.png',
      };

      if (isGuest) {
        DummyData.timeoff.insert(0, {
          ...recordMap,
          'id': 'guest_to_${DateTime.now().millisecondsSinceEpoch}',
        });
      } else {
        await FirestoreService().addTimeOffRecord(recordMap);
      }

      if (mounted) {
        FlashySnackBar.show(context, message: 'assign_time_off_success'.tr());
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
}
