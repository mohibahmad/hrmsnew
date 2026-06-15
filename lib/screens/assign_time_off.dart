import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../utils/snackbar_utils.dart';
import '../utils/logout_dialog.dart';

class AssignTimeOffScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onNotificationTap;
  const AssignTimeOffScreen({
    super.key,
    required this.onBack,
    this.onNotificationTap,
  });

  @override
  State<AssignTimeOffScreen> createState() => _AssignTimeOffScreenState();
}

class _AssignTimeOffScreenState extends State<AssignTimeOffScreen> {
  String _timeOffType = 'Annual Leave';
  DateTime _startDate = DateTime(2025, 1, 1);
  DateTime _endDate = DateTime(2025, 1, 10);
  final TextEditingController _notesController = TextEditingController();

  // Helper to format date as DD/MM/YYYY
  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final initialDate = isStartDate ? _startDate : _endDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0247C4),
              onPrimary: Color(0xFFFFFFFF),
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 9));
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate.subtract(const Duration(days: 9));
            if (_startDate.isBefore(DateTime(2020))) {
              _startDate = DateTime(2020);
            }
          }
        }
      });
    }
  }

  int get _requestedDays {
    return _endDate.difference(_startDate).inDays + 1;
  }

  @override
  void dispose() {
    _notesController.dispose();
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
                  const Text(
                    'Assign Time Off',
                    style: TextStyle(
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
    final name = user?.displayName ?? 'User';

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
          const Text(
            "Workforce",
            style: TextStyle(
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
              height: 24,
              width: 24,
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
                    const Text(
                      'Logout',
                      style: TextStyle(
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopForm(),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: _buildCalendar('MAY 2025', selectedDay: 1)),
              const SizedBox(width: 24),
              Expanded(child: _buildCalendar('MAY 2025', selectedDay: 1)),
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
          child: _buildLabeledDropdown('Time Off Type', _timeOffType),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'Start Date',
            _formatDate(_startDate),
            isStart: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _buildLabeledInput(
            'End Date',
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
                  borderRadius: BorderRadius.circular(4),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                final isGuest = AuthService().currentUser?.isAnonymous ?? false;
                final recordMap = {
                  'name': 'John Smith',
                  'email': 'john.smith@stark.com',
                  'position': 'Senior Web Developer',
                  'contact': '+1 555-0101',
                  'action': _timeOffType,
                };
                if (isGuest) {
                  final newId = 'dummy_t${DateTime.now().millisecondsSinceEpoch}';
                  DummyData.timeoff.insert(0, {
                    ...recordMap,
                    'id': newId,
                  });
                } else {
                  try {
                    await FirestoreService().addTimeOffRecord(recordMap);
                  } catch (e) {
                    debugPrint('Error saving time off record: $e');
                  }
                }

                // Show assign success confirmation
                FlashySnackBar.show(
                  context,
                  message:
                      'Successfully assigned $_timeOffType from ${_formatDate(_startDate)} to ${_formatDate(_endDate)} ($_requestedDays days)',
                );
                // Return to Time Off screen after a short delay
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted) {
                    widget.onBack();
                  }
                });
              },
              child: const Text(
                'Assign',
                style: TextStyle(
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
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
              items: const [
                DropdownMenuItem(
                  value: 'Annual Leave',
                  child: Text('Annual Leave'),
                ),
                DropdownMenuItem(
                  value: 'Sick Leave',
                  child: Text('Sick Leave'),
                ),
                DropdownMenuItem(
                  value: 'Casual Leave',
                  child: Text('Casual Leave'),
                ),
                DropdownMenuItem(
                  value: 'Maternity Leave',
                  child: Text('Maternity Leave'),
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
              borderRadius: BorderRadius.circular(4),
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

  Widget _buildCalendar(String monthYear, {int selectedDay = 1}) {
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
              const Icon(Icons.chevron_left, size: 20, color: Colors.black),
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
              const Icon(Icons.chevron_right, size: 20, color: Colors.black),
            ],
          ),
          const SizedBox(height: 16),
          _buildWeekdayRow(),
          const SizedBox(height: 12),
          _buildDaysGrid(selectedDay),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow() {
    return Row(
      children: [
        Expanded(child: _buildWeekday('SUN', Colors.red)),
        const SizedBox(width: 8),
        Expanded(child: _buildWeekday('MON', const Color(0xFF0247C4))),
        const SizedBox(width: 8),
        Expanded(child: _buildWeekday('TUE', const Color(0xFF0247C4))),
        const SizedBox(width: 8),
        Expanded(child: _buildWeekday('WED', const Color(0xFF0247C4))),
        const SizedBox(width: 8),
        Expanded(child: _buildWeekday('THU', const Color(0xFF0247C4))),
        const SizedBox(width: 8),
        Expanded(child: _buildWeekday('FRI', const Color(0xFF4CAF50))), // Green
        const SizedBox(width: 8),
        Expanded(child: _buildWeekday('SAT', const Color(0xFF0247C4))),
      ],
    );
  }

  Widget _buildWeekday(String day, Color color) {
    return Container(
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        day,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildDaysGrid(int selectedDay) {
    List<Widget> rows = [];
    int currentDay = 1;

    for (int i = 0; i < 5; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        // Leave SUN blank on first row based on image layout
        if (i == 0 && j == 0) {
          rowChildren.add(Expanded(child: _buildDayCell('')));
        } else if (currentDay <= 31) {
          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$currentDay',
                isSelected: currentDay == selectedDay,
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
      if (i < 4) rows.add(const SizedBox(height: 8)); // Space between rows
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(String day, {bool isSelected = false}) {
    if (day.isEmpty) return const SizedBox();
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.red : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.red : Colors.grey.shade300,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          day,
          style: TextStyle(
            color: isSelected ? Color(0xFFFFFFFF) : Colors.black,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'SF Pro Display',
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
              const Text(
                'Notes',
                style: TextStyle(
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
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: TextField(
                  controller: _notesController,
                  maxLines: null,
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Please enter your notes',
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
                  'Available Annual Leave Days',
                  '-1',
                  Colors.red,
                ),
                _buildSummaryRow(
                  'Requested Days',
                  '$_requestedDays',
                  Colors.black,
                ),
                _buildSummaryRow(
                  'Remaining Days',
                  '${-1 - _requestedDays}',
                  Colors.red,
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
}
