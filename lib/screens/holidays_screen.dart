import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/snackbar_utils.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';

class HolidaysScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const HolidaysScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  bool isDataEmpty = false;

  Map<String, List<HolidayItem>> _holidaysByMonth = {};

  @override
  void initState() {
    super.initState();
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _holidaysByMonth = DummyData.holidays.map((month, list) {
        return MapEntry(
          month,
          list.map((h) => HolidayItem(
            h['day'] as int,
            h['name'] as String,
            h['isEnabled'] as bool,
          )).toList(),
        );
      });
    } else {
      _holidaysByMonth = {};
    }
    // Automatically show the dialog after the screen renders to match the mockup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAddHolidayModal(context);
    });
  }

  void _showAddHolidayModal(BuildContext context) {
    final holidayNameController = TextEditingController();
    int selectedDay = 1;
    String selectedMonth = 'May';

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modal Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const Text(
                          'Add Holiday',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () {
                            if (holidayNameController.text.isNotEmpty) {
                              setState(() {
                                if (!_holidaysByMonth.containsKey(
                                  selectedMonth,
                                )) {
                                  _holidaysByMonth[selectedMonth] = [];
                                }
                                _holidaysByMonth[selectedMonth]!.insert(
                                  0,
                                  HolidayItem(
                                    selectedDay,
                                    holidayNameController.text,
                                    true,
                                  ),
                                );
                              });
                              Navigator.of(context).pop();
                              FlashySnackBar.show(
                                context,
                                message:
                                    'Successfully added holiday "${holidayNameController.text}"',
                              );
                            }
                          },
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Input Field
                    const Text(
                      'Holiday Name',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: holidayNameController,
                        decoration: InputDecoration.collapsed(
                          hintText: 'Labour Day',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Calendar Widget inside Modal
                    _buildModalCalendar(selectedDay, (day) {
                      setModalState(() {
                        selectedDay = day;
                      });
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalCalendar(int selectedDay, ValueChanged<int> onDaySelected) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.chevron_left, size: 20, color: Colors.black),
            SizedBox(width: 32),
            Text(
              'MAY 2025',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
            SizedBox(width: 32),
            Icon(Icons.chevron_right, size: 20, color: Colors.black),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildWeekday('SUN', Colors.red)),
            const SizedBox(width: 6),
            Expanded(child: _buildWeekday('MON', const Color(0xFF0247C4))),
            const SizedBox(width: 6),
            Expanded(child: _buildWeekday('TUE', const Color(0xFF0247C4))),
            const SizedBox(width: 6),
            Expanded(child: _buildWeekday('WED', const Color(0xFF0247C4))),
            const SizedBox(width: 6),
            Expanded(child: _buildWeekday('THU', const Color(0xFF0247C4))),
            const SizedBox(width: 6),
            Expanded(child: _buildWeekday('FRI', const Color(0xFF4CAF50))),
            const SizedBox(width: 6),
            Expanded(child: _buildWeekday('SAT', const Color(0xFF0247C4))),
          ],
        ),
        const SizedBox(height: 12),
        _buildDaysGrid(selectedDay, onDaySelected),
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
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildDaysGrid(int selectedDay, ValueChanged<int> onDaySelected) {
    List<Widget> rows = [];
    int currentDay = 1;

    for (int i = 0; i < 5; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        if (i == 0 && j == 0) {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null)));
        } else if (currentDay <= 31) {
          final day = currentDay;
          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$day',
                day == selectedDay,
                () => onDaySelected(day),
              ),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null)));
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 6));
      }
      rows.add(Row(children: rowChildren));
      if (i < 4) rows.add(const SizedBox(height: 6));
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(String day, bool isSelected, VoidCallback? onTap) {
    if (day.isEmpty) return const SizedBox();
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: onTap,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopActionRow(context),
                  const SizedBox(height: 24),
                  isDataEmpty || _holidaysByMonth.values.every((l) => l.isEmpty)
                      ? _buildEmptyState()
                      : _buildFilledState(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= MAIN CONTENT =================

  Widget _buildHeader(BuildContext context) {
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
            children: const [
              Text(
                'Workforce',
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
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: CircleAvatar(
              radius: 19,
              backgroundImage: const AssetImage(
                'assets/profileimage.png',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Holiday List',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _showAddHolidayModal(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0247C4),
            minimumSize: const Size(140, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: SvgPicture.asset(
            'assets/holidays_icon.svg',
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              Color(0xFFFFFFFF),
              BlendMode.srcIn,
            ),
          ),
          label: const Text(
            'Add Holiday',
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  // ================= FILLED STATE (LIST) =================

  Widget _buildFilledState() {
    final months = _holidaysByMonth.keys
        .where((m) => _holidaysByMonth[m]!.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: months.map((month) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: _buildMonthGroup(month, _holidaysByMonth[month]!),
        );
      }).toList(),
    );
  }

  Widget _buildMonthGroup(String month, List<HolidayItem> holidays) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          month,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF000000),
            fontWeight: FontWeight.w600,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 12),
        ...holidays.map((holiday) => _buildListItem(holiday)),
      ],
    );
  }

  Widget _buildListItem(HolidayItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9), // Light grey circle
              shape: BoxShape.circle,
            ),
            child: Text(
              '${item.day}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            item.name,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF000000),
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
          const Spacer(),
          // CupertinoSwitch matches iOS toggles in style
          Transform.scale(
            scale: 0.8,
            child: CupertinoSwitch(
              value: item.isEnabled,
              activeTrackColor: const Color(0xFF0247C4),
              inactiveTrackColor: Colors.grey.shade300,
              onChanged: (bool value) {
                setState(() {
                  item.isEnabled = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ================= EMPTY STATE =================

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/boy.png',
                width: 120,
                height: 100,
                colorFilter: const ColorFilter.mode(
                  Color(0xFFCBCBCB),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Holidays Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0247C4),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Data Model for Holiday Items
class HolidayItem {
  final int day;
  final String name;
  bool isEnabled;

  HolidayItem(this.day, this.name, this.isEnabled);
}
