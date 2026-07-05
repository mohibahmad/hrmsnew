import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter/cupertino.dart' hide GestureDetector;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/snackbar_utils.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../utils/premium_gate.dart';

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
  Map<String, List<HolidayItem>> _holidaysByMonth = {};
  bool _isLoading = false;
  StreamSubscription? _holidaysSub;

  @override
  void dispose() {
    _holidaysSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _holidaysByMonth = DummyData.holidays.map((month, list) {
        return MapEntry(
          month,
          list
              .map(
                (h) => HolidayItem(
                  h['day'] as int,
                  h['name'] as String,
                  h['isEnabled'] as bool,
                  month: month,
                ),
              )
              .toList(),
        );
      });
    } else {
      _isLoading = true;
      _holidaysSub = FirestoreService().holidaysStream.listen(
        (snapshot) {
          if (mounted) {
            final tempMap = <String, List<HolidayItem>>{};
            final sortedDocs = snapshot.docs.toList();
            sortedDocs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['createdAt'];
              final bTime = bData['createdAt'];
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return -1;
              if (bTime == null) return 1;
              if (aTime is Timestamp && bTime is Timestamp) {
                return bTime.compareTo(aTime);
              }
              return 0;
            });
            for (final doc in sortedDocs) {
              final data = doc.data() as Map<String, dynamic>;
              final month = (data['month'] ?? 'May').toString();
              final day = (data['day'] as num?)?.toInt() ?? 1;
              final name = (data['name'] ?? '').toString();
              bool isEnabled =
                  data['isEnabled'] == true || data['isEnabled'] == null;
              final id = doc.id;

              if (!tempMap.containsKey(month)) {
                tempMap[month] = [];
              }
              tempMap[month]!.add(
                HolidayItem(day, name, isEnabled, id: id, month: month),
              );
            }
            setState(() {
              _holidaysByMonth = tempMap;
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    }
  }

  void _showAddHolidayModal(BuildContext context) {
    final holidayNameController = TextEditingController();
    int selectedDay = DateTime.now().day;
    DateTime calendarDate = DateTime.now();
    const months = [
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
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String selectedMonthName = months[calendarDate.month - 1];
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              backgroundColor: Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 400,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
                        Text(
                          'add_holiday'.tr(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                           onPressed: () async {
                             if (holidayNameController.text.isNotEmpty) {
                               final dateObj = DateTime(
                                 calendarDate.year,
                                 calendarDate.month,
                                 selectedDay,
                               );
                               final dayOfWeekName =
                                   weekdays[dateObj.weekday - 1];
                               final remainingDaysVal = dateObj
                                   .difference(DateTime.now())
                                   .inDays;
                               final remainingDaysStr = remainingDaysVal > 0
                                   ? remainingDaysVal.toString().padLeft(2, '0')
                                   : '00';

                               final existingInMonth = _holidaysByMonth[selectedMonthName] ?? [];
                               final alreadyExists = existingInMonth.any((h) => h.day == selectedDay);
                               if (alreadyExists) {
                                 if (!context.mounted) return;
                                 FlashySnackBar.show(
                                   context,
                                   message: 'holiday_already_exists'.tr(),
                                   isError: true,
                                 );
                                 return;
                               }

                               final holidayMap = {
                                'day': selectedDay,
                                'month': selectedMonthName,
                                'remainingDays': remainingDaysStr,
                                'dayOfWeek': dayOfWeekName,
                                'name': holidayNameController.text,
                                'isEnabled': true,
                                'isCustom': true,
                                'year': calendarDate.year,
                              };
                              final isGuest =
                                  AuthService().currentUser?.isAnonymous ??
                                  false;
                              if (isGuest) {
                                setState(() {
                                  if (!_holidaysByMonth.containsKey(
                                    selectedMonthName,
                                  )) {
                                    _holidaysByMonth[selectedMonthName] = [];
                                  }
                                  final newItem = HolidayItem(
                                    selectedDay,
                                    holidayNameController.text,
                                    true,
                                    month: selectedMonthName,
                                  );
                                  _holidaysByMonth[selectedMonthName]!.insert(
                                    0,
                                    newItem,
                                  );
                                  if (!DummyData.holidays.containsKey(
                                    selectedMonthName,
                                  )) {
                                    DummyData.holidays[selectedMonthName] = [];
                                  }
                                  DummyData.holidays[selectedMonthName]!
                                      .insert(0, {
                                        'day': selectedDay,
                                        'month': selectedMonthName,
                                        'remainingDays': remainingDaysStr,
                                        'dayOfWeek': dayOfWeekName,
                                        'name': holidayNameController.text,
                                        'isEnabled': true,
                                      });
                                  DummyData.saveToPrefs();
                                });
                              } else {
                                await FirestoreService().addHoliday(holidayMap);
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              FlashySnackBar.show(
                                context,
                                message: 'successfully_added_holiday'.tr(
                                  namedArgs: {
                                    'name': holidayNameController.text,
                                  },
                                ),
                              );
                            }
                          },
                           child: Text(
                             'save'.tr(),
                             style: TextStyle(
                               color: Color(0xFFFFFFFF),
                               fontSize: 16,
                               fontWeight: FontWeight.bold,
                               fontFamily: 'SF Pro Display',
                             ),
                           ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Input Field
                    Text(
                      'holiday_name'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: holidayNameController,
                        decoration: InputDecoration.collapsed(
                          hintText: 'Enter holiday name',
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
                    const SizedBox(height: 16),

                    // Calendar Widget inside Modal
                    _buildModalCalendar(
                      calendarDate,
                      selectedDay,
                      (day) {
                        setModalState(() {
                          selectedDay = day;
                        });
                      },
                      (newDate) {
                        setModalState(() {
                          calendarDate = newDate;
                          int daysInNewMonth = DateTime(
                            newDate.year,
                            newDate.month + 1,
                            0,
                          ).day;
                          if (selectedDay > daysInNewMonth) {
                            selectedDay = daysInNewMonth;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalCalendar(
    DateTime calendarDate,
    int selectedDay,
    ValueChanged<int> onDaySelected,
    ValueChanged<DateTime> onMonthChanged,
  ) {
    String monthYearStr =
        '${DateFormat('MMMM', context.locale.toString()).format(calendarDate).toUpperCase()} ${calendarDate.year}';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month - 1, 1),
                );
              },
             child: const Icon(
                Icons.chevron_right,
                size: 16,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildWeekday('weekday_sun'.tr(), const Color(0xFFFF0004)),
            const SizedBox(width: 8),
            _buildWeekday('weekday_mon'.tr(), const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekday('weekday_tue'.tr(), const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekday('weekday_wed'.tr(), const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekday('weekday_thu'.tr(), const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekday('weekday_fri'.tr(), const Color(0xFF4AC000)),
            const SizedBox(width: 8),
            _buildWeekday('weekday_sat'.tr(), const Color(0xFF0247C4)),
          ],
        ),
        const SizedBox(height: 12),
        _buildDaysGrid(calendarDate, selectedDay, onDaySelected),
      ],
    );
  }

  Widget _buildWeekday(String day, Color color) {
    String shortDay = day;
    if (shortDay.length > 3) shortDay = shortDay.substring(0, 3);

    return Expanded(
      child: Container(
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
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }

  Widget _buildDaysGrid(
    DateTime calendarDate,
    int selectedDay,
    ValueChanged<int> onDaySelected,
  ) {
    List<Widget> rows = [];
    int daysInMonth = DateTime(
      calendarDate.year,
      calendarDate.month + 1,
      0,
    ).day;
    int firstWeekday = DateTime(
      calendarDate.year,
      calendarDate.month,
      1,
    ).weekday;
    int startOffset = firstWeekday == 7 ? 0 : firstWeekday;

    int currentDay = 1;

    for (int i = 0; i < 6; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        int index = i * 7 + j;
        if (index < startOffset) {
          rowChildren.add(_buildDayCell('', false, null, null));
        } else if (currentDay <= daysInMonth) {
          final int tapDay = currentDay;
          final bool isSelected = (currentDay == selectedDay);
          final cellDate = DateTime(calendarDate.year, calendarDate.month, currentDay);
          rowChildren.add(
            _buildDayCell('$currentDay', isSelected, () {
              onDaySelected(tapDay);
            }, cellDate),
          );
          currentDay++;
        } else {
          rowChildren.add(_buildDayCell('', false, null, null));
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 8));
      }
      rows.add(Row(children: rowChildren));
      if (currentDay > daysInMonth && i >= 4) break;
      if (i < 5) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(String day, bool isSelected, VoidCallback? onTap, DateTime? date) {
    if (day.isEmpty) {
      return const Expanded(
        child: AspectRatio(aspectRatio: 1, child: SizedBox()),
      );
    }
    final isSunday = date?.weekday == 7;
    final isFriday = date?.weekday == 5;
    final dayColor = isSunday
        ? const Color(0xFFFF0004)
        : (isFriday ? const Color(0xFF4AC000) : Colors.black);
    final selectedBg = isFriday ? const Color(0xFF4AC000) : const Color(0xFFFF0004);
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? selectedBg
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
                color: isSelected ? Color(0xFFFFFFFF) : dayColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
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
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (_holidaysByMonth.values.every((l) => l.isEmpty)
                            ? _buildEmptyState()
                            : _buildFilledState()),
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
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: const UserAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'holiday_list'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            final isPremium = await PreferencesService.isPremium();
            if (!mounted) return;
            final isGuest = AuthService().currentUser?.isAnonymous ?? false;
            if (!PremiumGate.canAddEntry(
              currentEntryCount: _holidaysByMonth.values.fold<int>(
                0,
                (sum, list) => sum + list.length,
              ),
              isPremium: isPremium,
              isGuest: isGuest,
            )) {
              final upgraded = await PremiumGate.shouldShowUpgradeDialog(
                context,
              );
              if (upgraded == true && mounted) {
                _showAddHolidayModal(context);
              }
              return;
            }
            if (!mounted) return;
            _showAddHolidayModal(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0247C4),
            minimumSize: const Size(32, 55),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: 0,
          ),
          icon: SvgPicture.asset(
            'assets/holidays_icon.svg',
            width: 22,
            height: 22,
            colorFilter: const ColorFilter.mode(
              Color(0xFFFFFFFF),
              BlendMode.srcIn,
            ),
          ),
          label: Text(
            'add_holiday'.tr(),
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w500,
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
          _localizeMonth(month),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
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
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 16),
          // CupertinoSwitch matches iOS toggles in style
          Transform.scale(
            scale: 0.8,
            child: CupertinoSwitch(
              value: item.isEnabled,
              activeTrackColor: const Color(0xFF0247C4),
              inactiveTrackColor: Colors.grey.shade300,
              onChanged: (bool value) async {
                setState(() {
                  item.isEnabled = value;
                });
                final isGuest = AuthService().currentUser?.isAnonymous ?? false;
                if (!isGuest && item.id != null) {
                  try {
                    await FirestoreService().updateHoliday(item.id!, {
                      'isEnabled': value,
                    });
                  } catch (e) {
                    setState(() {
                      item.isEnabled = !value;
                    });
                    if (mounted) {
                      FlashySnackBar.show(
                        context,
                        message: 'error_updating_holiday'.tr(
                          namedArgs: {'error': e.toString()},
                        ),
                      );
                    }
                  }
                } else if (isGuest) {
                  final monthList = DummyData.holidays[item.month];
                  if (monthList != null) {
                    for (var h in monthList) {
                      if (h['day'] == item.day && h['name'] == item.name) {
                        h['isEnabled'] = value;
                        break;
                      }
                    }
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/placeholdemptystate.png',
                width: 120,
                height: 100,
                color: const Color(0xFFCBCBCB),
              ),
              const SizedBox(height: 16),
              Text(
                'no_holidays_found'.tr(),
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

  String _localizeMonth(String month) {
    switch (month) {
      case 'January':
        return 'month_january'.tr();
      case 'February':
        return 'month_february'.tr();
      case 'March':
        return 'month_march'.tr();
      case 'April':
        return 'month_april'.tr();
      case 'May':
        return 'month_may'.tr();
      case 'June':
        return 'month_june'.tr();
      case 'July':
        return 'month_july'.tr();
      case 'August':
        return 'month_august'.tr();
      case 'September':
        return 'month_september'.tr();
      case 'October':
        return 'month_october'.tr();
      case 'November':
        return 'month_november'.tr();
      case 'December':
        return 'month_december'.tr();
      default:
        return month;
    }
  }
}

// Data Model for Holiday Items
class HolidayItem {
  final String? id;
  final String month;
  final int day;
  final String name;
  bool isEnabled;

  HolidayItem(
    this.day,
    this.name,
    this.isEnabled, {
    this.id,
    required this.month,
  });
}
