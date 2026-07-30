import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/snackbar_utils.dart';
import '../utils/delete_dialog.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../utils/premium_gate.dart';
import '../utils/rate_us_helper.dart';
import '../widgets/notification_bell.dart';
import '../utils/guest_restriction.dart';

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
  Set<int> _companyWorkingDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  bool _isLoading = false;
  StreamSubscription? _holidaysSub;
  late AuthService _authService;
  late FirestoreService _firestore;
  bool _initialized = false;

  @override
  void dispose() {
    _holidaysSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _holidaysByMonth = DummyData.holidays.map((month, list) {
        return MapEntry(
          month,
          list.map((h) {
            final dateStr = (h['date'] ?? '').toString();
            final parts = dateStr.split('/');
            int day = 1;
            if (parts.length == 3) {
              day = int.tryParse(parts[0]) ?? 1;
            }
            return HolidayItem(
              (h['day'] as num?)?.toInt() ?? day,
              h['name'] as String,
              (h['isEnabled'] as bool?) ?? true,
              month: month,
              year: (h['year'] as num?)?.toInt(),
              isRecurring: h['isRecurring'] == true,
            );
          }).toList(),
        );
      });
      PreferencesService.getCompanyWorkingDays().then((days) {
        if (mounted) setState(() => _companyWorkingDays = days);
      });
    } else {
      _isLoading = true;
      _holidaysSub = _firestore.holidaysStream.listen(
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
            var workingDays = _companyWorkingDays;
            for (final doc in sortedDocs) {
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
              final month = (data['month'] ?? 'May').toString();
              final day = (data['day'] as num?)?.toInt() ?? 1;
              final name = (data['name'] ?? '').toString();
              final year = (data['year'] as num?)?.toInt();
              final isRecurring = data['isRecurring'] == true;
              bool isEnabled =
                  data['isEnabled'] == true || data['isEnabled'] == null;
              final id = doc.id;

              if (!tempMap.containsKey(month)) {
                tempMap[month] = [];
              }
              tempMap[month]!.add(
                HolidayItem(
                  day,
                  name,
                  isEnabled,
                  id: id,
                  month: month,
                  year: year,
                  isRecurring: isRecurring,
                ),
              );
            }
            setState(() {
              _holidaysByMonth = tempMap;
              _companyWorkingDays = workingDays;
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

  static const Map<int, String> _weekdayKeys = {
    DateTime.monday: 'weekday_monday',
    DateTime.tuesday: 'weekday_tuesday',
    DateTime.wednesday: 'weekday_wednesday',
    DateTime.thursday: 'weekday_thursday',
    DateTime.friday: 'weekday_friday',
    DateTime.saturday: 'weekday_saturday',
    DateTime.sunday: 'weekday_sunday',
  };

  String _weekdayLabel(int day) => (_weekdayKeys[day] ?? '').tr();

  Widget _buildWorkDaysSectionTitle({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  Future<void> _showCompanyWorkDaysModal() async {
    final selectedDays = Set<int>.from(_companyWorkingDays);
    var isSaving = false;
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final offDays = _weekdayKeys.keys
              .where((day) => !selectedDays.contains(day))
              .toList();
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(
              'company_work_days'.tr(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro Display',
              ),
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'company_work_days_help'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildWorkDaysSectionTitle(
                    icon: Icons.business_center_rounded,
                    title: 'working_days'.tr(),
                    color: const Color(0xFF0247C4),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _weekdayKeys.keys.map((day) {
                      final selected = selectedDays.contains(day);
                      return FilterChip(
                        selected: selected,
                        showCheckmark: true,
                        selectedColor: const Color(0xFFDCE8FF),
                        checkmarkColor: const Color(0xFF0247C4),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF0247C4)
                              : const Color(0xFFCBD5E1),
                        ),
                        label: Text(_weekdayLabel(day)),
                        onSelected: (value) {
                          setModalState(() {
                            if (value) {
                              selectedDays.add(day);
                            } else {
                              selectedDays.remove(day);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  _buildWorkDaysSectionTitle(
                    icon: Icons.weekend_rounded,
                    title: 'company_off_days'.tr(),
                    color: const Color(0xFFD81B1F),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    offDays.isEmpty
                        ? 'none'.tr()
                        : offDays.map(_weekdayLabel).join(', '),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr()),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0247C4),
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        setModalState(() => isSaving = true);
                        if (selectedDays.isEmpty) {
                          setModalState(() => isSaving = false);
                          FlashySnackBar.show(
                            context,
                            message: 'select_at_least_one_work_day'.tr(),
                            isError: true,
                          );
                          return;
                        }
                        try {
                          final isGuest =
                              _authService.currentUser?.isAnonymous ?? false;
                          if (isGuest) {
                            await PreferencesService.setCompanyWorkingDays(
                              selectedDays,
                            );
                          } else {
                            await _firestore.setCompanyWorkingDays(
                              selectedDays,
                            );
                          }
                          if (!mounted || !dialogContext.mounted) return;
                          setState(() {
                            _companyWorkingDays = Set<int>.from(selectedDays);
                          });
                          Navigator.of(dialogContext).pop();
                          FlashySnackBar.show(
                            this.context,
                            message: 'company_work_days_saved'.tr(),
                          );
                        } catch (error) {
                          setModalState(() => isSaving = false);
                          if (!context.mounted) return;
                          FlashySnackBar.show(
                            context,
                            message: error.toString(),
                            isError: true,
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('save'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddHolidayModal(BuildContext parentContext) {
    final holidayNameController = TextEditingController();
    int? selectedDay = DateTime.now().day;
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
    var isSaving = false;
    showDialog(
      context: parentContext,
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
                              borderRadius: BorderRadius.circular(4),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setModalState(() => isSaving = true);
                                  if (selectedDay == null) {
                                    setModalState(() => isSaving = false);
                                    if (!context.mounted) return;
                                    FlashySnackBar.show(
                                      context,
                                      message: 'Please select a day',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  final holidayName = holidayNameController.text
                                      .trim();
                                  if (holidayName.isNotEmpty) {
                                    final dateObj = DateTime(
                                      calendarDate.year,
                                      calendarDate.month,
                                      selectedDay!,
                                    );
                                    final dayOfWeekName = _weekdayLabel(
                                      dateObj.weekday,
                                    );
                                    final remainingDaysVal = dateObj
                                        .difference(DateTime.now())
                                        .inDays;
                                    final remainingDaysStr =
                                        remainingDaysVal > 0
                                        ? remainingDaysVal.toString().padLeft(
                                            2,
                                            '0',
                                          )
                                        : '00';

                                    final existingInMonth =
                                        _holidaysByMonth[selectedMonthName] ??
                                        [];
                                    final alreadyExists = existingInMonth.any(
                                      (h) =>
                                          h.day == selectedDay &&
                                          h.name ==
                                              holidayNameController.text.trim(),
                                    );
                                    if (alreadyExists) {
                                      setModalState(() => isSaving = false);
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
                                      'name': holidayName,
                                      'isEnabled': true,
                                      'isCustom': true,
                                      'year': calendarDate.year,
                                      'isRecurring': false,
                                    };
                                    final isGuest =
                                        _authService.currentUser?.isAnonymous ??
                                        false;
                                    try {
                                      if (isGuest) {
                                        setState(() {
                                          if (!_holidaysByMonth.containsKey(
                                            selectedMonthName,
                                          )) {
                                            _holidaysByMonth[selectedMonthName] =
                                                [];
                                          }
                                          final newItem = HolidayItem(
                                            selectedDay!,
                                            holidayName,
                                            true,
                                            month: selectedMonthName,
                                            year: calendarDate.year,
                                          );
                                          _holidaysByMonth[selectedMonthName]!
                                              .insert(0, newItem);
                                          if (!DummyData.holidays.containsKey(
                                            selectedMonthName,
                                          )) {
                                            DummyData
                                                    .holidays[selectedMonthName] =
                                                [];
                                          }
                                          DummyData.holidays[selectedMonthName]!
                                              .insert(0, {
                                                'day': selectedDay,
                                                'month': selectedMonthName,
                                                'remainingDays':
                                                    remainingDaysStr,
                                                'dayOfWeek': dayOfWeekName,
                                                'name': holidayName,
                                                'isEnabled': true,
                                                'year': calendarDate.year,
                                                'isRecurring': false,
                                              });
                                          DummyData.saveToPrefs();
                                        });
                                      } else {
                                        await _firestore.addHoliday(holidayMap);
                                      }
                                    } catch (e) {
                                      setModalState(() => isSaving = false);
                                      if (!context.mounted) return;
                                      FlashySnackBar.show(
                                        context,
                                        message: 'failed_to_add_holiday'.tr(
                                          namedArgs: {'error': e.toString()},
                                        ),
                                        isError: true,
                                      );
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                    FlashySnackBar.show(
                                      parentContext,
                                      message: 'successfully_added_holiday'.tr(
                                        namedArgs: {
                                          'name': holidayNameController.text,
                                        },
                                      ),
                                    );
                                    if (parentContext.mounted) {
                                      tryShowFirstMilestoneRateUs('holiday');
                                    }
                                  } else {
                                    setModalState(() => isSaving = false);
                                    if (!context.mounted) return;
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_holiday_name'.tr(),
                                      isError: true,
                                    );
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'save'.tr(),
                                  style: TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

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
                        inputFormatters: [LengthLimitingTextInputFormatter(50)],
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
                          if (selectedDay! > daysInNewMonth) {
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
    int? selectedDay,
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
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_left, size: 20, color: Colors.black),
              ),
            ),
            Text(
              monthYearStr,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: () {
                onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month + 1, 1),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_right, size: 20, color: Colors.black),
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
    int? selectedDay,
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
          final bool isSelected =
              selectedDay != null && (currentDay == selectedDay);
          final cellDate = DateTime(
            calendarDate.year,
            calendarDate.month,
            currentDay,
          );
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

  Widget _buildDayCell(
    String day,
    bool isSelected,
    VoidCallback? onTap,
    DateTime? date,
  ) {
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
    final selectedBg = isFriday
        ? const Color(0xFF4AC000)
        : const Color(0xFFFF0004);
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
                  const SizedBox(height: 16),
                  _buildCompanyWorkDaysSummary(),
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
        Flexible(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  _showCompanyWorkDaysModal();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0247C4),
                  foregroundColor: const Color(0xFFFFFFFF),
                  minimumSize: const Size(32, 50),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(
                  Icons.edit_calendar_rounded,
                  size: 22,
                  color: Color(0xFFFFFFFF),
                ),
                label: Text(
                  'add_company_work_days'.tr(),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final isGuest =
                        _authService.currentUser?.isAnonymous ?? false;
                    if (isGuest) {
                      if (!mounted) return;
                      showGuestRestrictionDialog(context);
                      return;
                    }
                    final isPremium = await PreferencesService.isPremium();
                    if (!mounted) return;
                    if (!PremiumGate.canAddEntry(
                      currentEntryCount: _holidaysByMonth.values.fold<int>(
                        0,
                        (sum, list) => sum + list.length,
                      ),
                      isPremium: isPremium,
                      isGuest: isGuest,
                    )) {
                      final upgraded =
                          await PremiumGate.shouldShowUpgradeDialog(context);
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
                    minimumSize: const Size(32, 50),
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
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyWorkDaysSummary() {
    final workingDays = _weekdayKeys.keys
        .where(_companyWorkingDays.contains)
        .map(_weekdayLabel)
        .join(', ');
    final offDays = _weekdayKeys.keys
        .where((day) => !_companyWorkingDays.contains(day))
        .map(_weekdayLabel)
        .join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildDaySummary(
              Icons.business_center_rounded,
              'working_days'.tr(),
              workingDays,
              const Color(0xFF0247C4),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _buildDaySummary(
              Icons.weekend_rounded,
              'company_off_days'.tr(),
              offDays.isEmpty ? 'none'.tr() : offDays,
              const Color(0xFFD81B1F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySummary(
    IconData icon,
    String title,
    String days,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                days,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  Future<void> _deleteHoliday(HolidayItem item) async {
    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_holiday'.tr(),
      content: 'delete_holiday_desc'.tr(),
    );
    if (!confirmed) return;

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        final monthList = _holidaysByMonth[item.month];
        if (monthList != null) {
          monthList.removeWhere(
            (h) => h.day == item.day && h.name == item.name,
          );
          if (monthList.isEmpty) _holidaysByMonth.remove(item.month);
        }
      });
      final dummyMonthList = DummyData.holidays[item.month];
      if (dummyMonthList != null) {
        dummyMonthList.removeWhere(
          (h) => h['day'] == item.day && h['name'] == item.name,
        );
        if (dummyMonthList.isEmpty) DummyData.holidays.remove(item.month);
      }
      await DummyData.saveToPrefs();
    } else {
      if (item.id != null) {
        await _firestore.deleteHoliday(item.id!);
      }
    }
    if (mounted) {
      FlashySnackBar.show(context, message: 'holiday_deleted'.tr());
    }
  }

  void _editHoliday(HolidayItem item) {
    final holidayNameController = TextEditingController(text: item.name);
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
    int selectedDay = item.day;
    int monthIndex = months.indexOf(item.month);
    if (monthIndex < 0) monthIndex = DateTime.now().month - 1;
    DateTime calendarDate = DateTime(
      DateTime.now().year,
      monthIndex + 1,
      selectedDay,
    );

    var isSaving = false;
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
                          'edit_holiday'.tr(),
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
                              borderRadius: BorderRadius.circular(4),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setModalState(() => isSaving = true);
                                  if (holidayNameController.text
                                      .trim()
                                      .isNotEmpty) {
                                    final isGuest =
                                        _authService.currentUser?.isAnonymous ??
                                        false;
                                    try {
                                      if (isGuest) {
                                        setState(() {
                                          final oldMonthList =
                                              DummyData.holidays[item.month];

                                          Map<String, dynamic>? updatedHoliday;

                                          if (oldMonthList != null) {
                                            final index = oldMonthList
                                                .indexWhere(
                                                  (h) =>
                                                      h['day'] == item.day &&
                                                      h['name'] == item.name,
                                                );

                                            if (index != -1) {
                                              updatedHoliday =
                                                  Map<String, dynamic>.from(
                                                    oldMonthList[index],
                                                  );
                                              oldMonthList.removeAt(index);

                                              if (oldMonthList.isEmpty) {
                                                DummyData.holidays.remove(
                                                  item.month,
                                                );
                                              }
                                            }
                                          }

                                          updatedHoliday ??= {
                                            'isEnabled': item.isEnabled,
                                          };

                                          updatedHoliday['name'] =
                                              holidayNameController.text.trim();
                                          updatedHoliday['day'] = selectedDay;
                                          updatedHoliday['month'] =
                                              selectedMonthName;
                                          updatedHoliday['year'] =
                                              calendarDate.year;
                                          updatedHoliday['isRecurring'] =
                                              item.isRecurring;

                                          DummyData.holidays.putIfAbsent(
                                            selectedMonthName,
                                            () => [],
                                          );
                                          DummyData.holidays[selectedMonthName]!
                                              .insert(0, updatedHoliday);

                                          DummyData.saveToPrefs();

                                          _holidaysByMonth = DummyData.holidays
                                              .map((month, list) {
                                                return MapEntry(
                                                  month,
                                                  list.map((h) {
                                                    return HolidayItem(
                                                      h['day'] as int,
                                                      h['name'] as String,
                                                      h['isEnabled'] as bool? ??
                                                          true,
                                                      month: month,
                                                      year: (h['year'] as num?)
                                                          ?.toInt(),
                                                      isRecurring:
                                                          h['isRecurring'] ==
                                                          true,
                                                    );
                                                  }).toList(),
                                                );
                                              });
                                        });
                                      } else {
                                        if (item.id != null) {
                                          await _firestore
                                              .updateHoliday(item.id!, {
                                                'name': holidayNameController
                                                    .text
                                                    .trim(),
                                                'day': selectedDay,
                                                'month': selectedMonthName,
                                                'year': calendarDate.year,
                                                'isRecurring': item.isRecurring,
                                              });
                                        }
                                      }
                                    } catch (e) {
                                      setModalState(() => isSaving = false);
                                      if (!context.mounted) return;
                                      FlashySnackBar.show(
                                        context,
                                        message: 'failed_to_update_holiday'.tr(
                                          namedArgs: {'error': e.toString()},
                                        ),
                                        isError: true,
                                      );
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                    FlashySnackBar.show(
                                      context,
                                      message: 'holiday_updated'.tr(),
                                    );
                                  } else {
                                    setModalState(() => isSaving = false);
                                    if (!context.mounted) return;
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_holiday_name'.tr(),
                                      isError: true,
                                    );
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'save'.tr(),
                                  style: TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

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
                        inputFormatters: [LengthLimitingTextInputFormatter(50)],
                        decoration: InputDecoration.collapsed(
                          hintText: 'enter_holiday_name'.tr(),
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
                          if (selectedDay! > daysInNewMonth) {
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
              color: Color(0xFFF1F5F9),
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

          GestureDetector(
            onTap: () async {
              final value = !item.isEnabled;
              setState(() {
                item.isEnabled = value;
              });
              final isGuest = _authService.currentUser?.isAnonymous ?? false;
              if (!isGuest && item.id != null) {
                try {
                  await _firestore.updateHoliday(item.id!, {
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
                DummyData.saveToPrefs();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: 50,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: item.isEnabled
                    ? const Color(0xFF0247C4)
                    : const Color(0xFFD1D5DB),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: item.isEnabled
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '',
            icon: const Icon(
              Icons.more_vert,
              color: Color.fromARGB(255, 0, 0, 0),
              size: 20,
            ),
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: Color(0xFFCBCBCB)),
            ),
            color: const Color(0xFFFBFBFC),
            elevation: 4,
            onSelected: (value) {
              if (value == 'edit') {
                final isGuest = _authService.currentUser?.isAnonymous ?? false;
                if (isGuest) {
                  showGuestRestrictionDialog(context);
                  return;
                }
                _editHoliday(item);
              } else if (value == 'delete') {
                final isGuest = _authService.currentUser?.isAnonymous ?? false;
                if (isGuest) {
                  showGuestRestrictionDialog(context);
                  return;
                }
                _deleteHoliday(item);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                height: 36,
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/edit_icon.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF0247C4),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'edit'.tr(),
                      style: const TextStyle(
                        color: Color(0xFF0247C4),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                height: 36,
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/delete_icon.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        Colors.red,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'delete'.tr(),
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
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

class HolidayItem {
  final String? id;
  final String month;
  final int day;
  final String name;
  bool isEnabled;
  final int? year;
  final bool isRecurring;

  HolidayItem(
    this.day,
    this.name,
    this.isEnabled, {
    this.id,
    required this.month,
    this.year,
    this.isRecurring = false,
  });
}
