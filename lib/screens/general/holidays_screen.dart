import 'package:hrms/core/utils/calendar_widgets.dart';
import 'package:hrms/core/utils/utils.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/common/notification_bell.dart';
import 'package:hrms/widgets/common/screen_table_shimmer.dart';

class HolidaysScreen extends ConsumerStatefulWidget {
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
  ConsumerState<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends ConsumerState<HolidaysScreen> {
  Map<String, List<HolidayItem>> _holidaysByMonth = {};
  Set<int> _companyWorkingDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };

  bool _isLoading = false;

  late final AuthService _authService;
  late final FirestoreService _firestore;

  bool _initialized = false;
  final Set<String> _updatingHolidayIds = <String>{};

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  static final List<String> _calendarMonths = LocalizationHelper
      .englishMonthNames
      .sublist(1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    if (_isGuest) {
      _loadGuestData();
    } else {
      _loadFirestoreData();
    }
  }

  void _loadGuestData() {
    _holidaysByMonth = _guestHolidayGroups();
    PreferencesService.getCompanyWorkingDays().then((days) {
      if (mounted) setState(() => _companyWorkingDays = days);
    });
  }

  void _loadFirestoreData() {
    _isLoading = true;
    ref.listenAsync(
      holidaysProvider,
      (records) {
        if (!mounted) return;
        final tempMap = <String, List<HolidayItem>>{};

        final sortedRecords = sortedFirestoreRecords(records, nullsLast: false);
        final calendar = splitCompanyCalendarRecords(
          sortedRecords,
          fallbackWorkingDays: _companyWorkingDays,
          acceptNumericStrings: true,
        );

        for (final data in calendar.holidays) {
          final storedDate = AppDateUtils.holidayRecordDate(data);
          final month = storedDate != null
              ? _calendarMonths[storedDate.month - 1]
              : _canonicalMonth(data['month']);
          final day = storedDate?.day ?? _intValue(data['day']);
          final name = (data['name'] ?? '').toString().trim();
          final year = storedDate?.year ?? _intValue(data['year']);

          if (month == null || day == null || name.isEmpty) continue;

          final monthNumber = _calendarMonths.indexOf(month) + 1;
          final maxDay = DateTime(year ?? 2024, monthNumber + 1, 0).day;
          if (day < 1 || day > maxDay) continue;

          tempMap
              .putIfAbsent(month, () => [])
              .add(
                HolidayItem(
                  day,
                  name,
                  data['isEnabled'] != false,
                  id: data['id']?.toString(),
                  month: month,
                  year: year,
                  isRecurring: data['isRecurring'] == true,
                ),
              );
        }

        setState(() {
          _holidaysByMonth = tempMap;
          _companyWorkingDays = calendar.workingDays;
          _isLoading = false;
        });
      },
      onError: (error, stackTrace) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim());
  }

  String? _canonicalMonth(dynamic value) {
    final raw = (value ?? '').toString().trim().replaceAll('.', '');
    if (raw.isEmpty) return null;

    final monthNumber = int.tryParse(raw);
    if (monthNumber != null && monthNumber >= 1 && monthNumber <= 12) {
      return _calendarMonths[monthNumber - 1];
    }

    final normalized = raw.toLowerCase();
    for (final month in _calendarMonths) {
      final lower = month.toLowerCase();
      if (lower == normalized || lower.substring(0, 3) == normalized) {
        return month;
      }
    }
    return null;
  }

  DateTime? _storedHolidayDate(dynamic value) {
    final parsed = AppDateUtils.dateFromValue(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Map<String, List<HolidayItem>> _guestHolidayGroups() {
    final result = <String, List<HolidayItem>>{};

    for (final entry in DummyData.holidays.entries) {
      for (final holiday in entry.value) {
        final storedDate = _storedHolidayDate(holiday['date']);
        final month =
            _canonicalMonth(holiday['month']) ??
            (storedDate == null
                ? _canonicalMonth(entry.key)
                : _calendarMonths[storedDate.month - 1]);
        final day = _intValue(holiday['day']) ?? storedDate?.day;
        final name = (holiday['name'] ?? '').toString().trim();
        final entryYear = int.tryParse(entry.key);
        final year =
            _intValue(holiday['year']) ?? storedDate?.year ?? entryYear;

        if (month == null || day == null || name.isEmpty) continue;

        final monthNumber = _calendarMonths.indexOf(month) + 1;
        final maxDay = DateTime(
          year ?? DateTime.now().year,
          monthNumber + 1,
          0,
        ).day;
        if (day < 1 || day > maxDay) continue;

        result
            .putIfAbsent(month, () => [])
            .add(
              HolidayItem(
                day,
                name,
                holiday['isEnabled'] != false,
                month: month,
                year: year,
                isRecurring: holiday['isRecurring'] == true,
                storageKey: entry.key,
              ),
            );
      }
    }
    return result;
  }

  bool _matchesGuestHoliday(Map<String, dynamic> holiday, HolidayItem item) {
    final storedDate = _storedHolidayDate(holiday['date']);
    final day = _intValue(holiday['day']) ?? storedDate?.day;
    return day == item.day &&
        (holiday['name'] ?? '').toString().trim() == item.name;
  }

  bool _isDuplicateHoliday({
    required String name,
    required String month,
    required int day,
    required int year,
    required bool isRecurring,
    String? excludingId,
    HolidayItem? excludingItem,
  }) {
    final normalizedName = name.trim().toLowerCase();
    for (final holiday in _holidaysByMonth[month] ?? <HolidayItem>[]) {
      if (excludingId != null && holiday.id == excludingId) continue;
      if (excludingItem != null && identical(holiday, excludingItem)) continue;
      if (holiday.day != day) continue;
      if (holiday.name.trim().toLowerCase() != normalizedName) continue;

      final existingRecurring = holiday.isRecurring || holiday.year == null;
      if (isRecurring || existingRecurring || holiday.year == year) return true;
    }
    return false;
  }

  String _weekdayLabel(int day) =>
      (LocalizationHelper.weekdayKeys[day] ?? '').tr();

  String _localizeMonth(String month) {
    final canonical = _canonicalMonth(month) ?? month;
    final index = LocalizationHelper.englishMonthNames.indexOf(canonical);
    return index > 0 ? LocalizationHelper.localizedMonth(index) : canonical;
  }

  Future<void> _showCompanyWorkDaysModal() async {
    final selectedDays = Set<int>.from(_companyWorkingDays);
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (_, setModalState) {
          final offDays = LocalizationHelper.weekdayKeys.keys
              .where((d) => !selectedDays.contains(d))
              .toList();

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(
              'company_work_days'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                    children: LocalizationHelper.weekdayKeys.keys.map((day) {
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
                        onSelected: (value) => setModalState(
                          () => value
                              ? selectedDays.add(day)
                              : selectedDays.remove(day),
                        ),
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
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogCtx).pop(),
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
                          if (_isGuest) {
                            await PreferencesService.setCompanyWorkingDays(
                              selectedDays,
                            );
                          } else {
                            await _firestore.setCompanyWorkingDays(
                              selectedDays,
                            );
                          }
                          if (!mounted || !dialogCtx.mounted) return;
                          setState(
                            () => _companyWorkingDays = Set<int>.from(
                              selectedDays,
                            ),
                          );
                          Navigator.of(dialogCtx).pop();
                          FlashySnackBar.show(
                            context,
                            message: 'company_work_days_saved'.tr(),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          setModalState(() => isSaving = false);
                          FlashySnackBar.show(
                            context,
                            message: 'failed_to_save_record'.tr(),
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

  Widget _buildHolidayDialog({
    required BuildContext parentContext,
    required String dialogTitle,
    required TextEditingController nameController,
    required int selectedDay,
    required DateTime calendarDate,
    required bool isSaving,
    required ValueChanged<int> onDaySelected,
    required ValueChanged<DateTime> onMonthChanged,
    required VoidCallback onSave,
    required VoidCallback onClose,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      backgroundColor: const Color(0xFFFFFFFF),
      elevation: 10,
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 20,
                      ),
                      onPressed: isSaving ? null : onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  Text(
                    dialogTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF000000),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
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
                      onPressed: isSaving ? null : onSave,
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
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'holiday_name'.tr(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF000000),
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
                controller: nameController,
                inputFormatters: [LengthLimitingTextInputFormatter(50)],
                decoration: InputDecoration.collapsed(
                  hintText: 'enter_holiday_name'.tr(),
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildModalCalendar(
              calendarDate,
              selectedDay,
              onDaySelected,
              onMonthChanged,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddHolidayModal(BuildContext parentContext) {
    final nameController = TextEditingController();
    int selectedDay = DateTime.now().day;
    DateTime calendarDate = DateTime.now();
    var isSaving = false;

    showDialog(
      context: parentContext,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final selectedMonthName = _calendarMonths[calendarDate.month - 1];

            Future<void> onSave() async {
              setModalState(() => isSaving = true);

              final holidayName = nameController.text.trim();

              if (selectedDay == 0 && holidayName.isEmpty) {
                setModalState(() => isSaving = false);
                if (!ctx.mounted) return;
                FlashySnackBar.show(
                  ctx,
                  message: 'please_fill_all_fields'.tr(),
                  isError: true,
                );
                return;
              }

              if (holidayName.isEmpty) {
                setModalState(() => isSaving = false);
                if (!ctx.mounted) return;
                FlashySnackBar.show(
                  ctx,
                  message: 'please_enter_holiday_name'.tr(),
                  isError: true,
                );
                return;
              }

              final alreadyExists = _isGuest
                  ? (_holidaysByMonth[selectedMonthName] ?? []).any(
                      (h) => h.day == selectedDay && h.name == holidayName,
                    )
                  : _isDuplicateHoliday(
                      name: holidayName,
                      month: selectedMonthName,
                      day: selectedDay,
                      year: calendarDate.year,
                      isRecurring: false,
                    );

              if (alreadyExists) {
                setModalState(() => isSaving = false);
                if (!ctx.mounted) return;
                FlashySnackBar.show(
                  ctx,
                  message: 'holiday_already_exists'.tr(),
                  isError: true,
                );
                return;
              }

              final dateObj = DateTime(
                calendarDate.year,
                calendarDate.month,
                selectedDay,
              );
              final holidayMap = {
                'date': dateObj,
                'name': holidayName,
                'isEnabled': true,
                'isCustom': true,
                'year': calendarDate.year,
                'isRecurring': false,
              };

              try {
                if (_isGuest) {
                  setState(() {
                    _holidaysByMonth
                        .putIfAbsent(selectedMonthName, () => [])
                        .insert(
                          0,
                          HolidayItem(
                            selectedDay,
                            holidayName,
                            true,
                            month: selectedMonthName,
                            year: calendarDate.year,
                          ),
                        );
                    DummyData.holidays
                        .putIfAbsent(selectedMonthName, () => [])
                        .insert(0, {
                          'date':
                              '${selectedDay.toString().padLeft(2, '0')}/${calendarDate.month.toString().padLeft(2, '0')}/${calendarDate.year}',
                          'name': holidayName,
                          'isEnabled': true,
                          'isRecurring': false,
                        });
                    DummyData.saveToPrefs();
                  });
                } else {
                  await _firestore.addHoliday(holidayMap);
                }
              } catch (e) {
                if (!ctx.mounted) return;
                setModalState(() => isSaving = false);
                FlashySnackBar.show(
                  ctx,
                  message: 'failed_to_add_holiday'.tr(
                    namedArgs: {'error': e.toString()},
                  ),
                  isError: true,
                );
                return;
              }

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (parentContext.mounted) {
                FlashySnackBar.show(
                  parentContext,
                  message: 'successfully_added_holiday'.tr(
                    namedArgs: {'name': holidayName},
                  ),
                );
                tryShowFirstMilestoneRateUs('holiday');
              }
            }

            return _buildHolidayDialog(
              parentContext: parentContext,
              dialogTitle: 'add_holiday'.tr(),
              nameController: nameController,
              selectedDay: selectedDay,
              calendarDate: calendarDate,
              isSaving: isSaving,
              onDaySelected: (day) => setModalState(() => selectedDay = day),
              onMonthChanged: (newDate) {
                setModalState(() {
                  calendarDate = newDate;
                  final maxDay = DateTime(
                    newDate.year,
                    newDate.month + 1,
                    0,
                  ).day;
                  if (selectedDay > maxDay) selectedDay = maxDay;
                });
              },
              onSave: onSave,
              onClose: () => Navigator.of(ctx).pop(),
            );
          },
        );
      },
    ).whenComplete(nameController.dispose);
  }

  void _editHoliday(HolidayItem item) {
    final nameController = TextEditingController(text: item.name);
    int monthIndex = _calendarMonths.indexOf(item.month);
    if (monthIndex < 0) monthIndex = DateTime.now().month - 1;

    final selectedYear = item.year ?? DateTime.now().year;
    final maxDay = DateTime(selectedYear, monthIndex + 2, 0).day;
    int selectedDay = item.day.clamp(1, maxDay);
    DateTime calendarDate = DateTime(selectedYear, monthIndex + 1, selectedDay);
    var isSaving = false;

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final selectedMonthName = _calendarMonths[calendarDate.month - 1];

            Future<void> onSave() async {
              setModalState(() => isSaving = true);

              final holidayName = nameController.text.trim();
              if (holidayName.isEmpty) {
                setModalState(() => isSaving = false);
                if (!ctx.mounted) return;
                FlashySnackBar.show(
                  ctx,
                  message: 'please_enter_holiday_name'.tr(),
                  isError: true,
                );
                return;
              }

              if (!_isGuest &&
                  _isDuplicateHoliday(
                    name: holidayName,
                    month: selectedMonthName,
                    day: selectedDay,
                    year: calendarDate.year,
                    isRecurring: item.isRecurring,
                    excludingId: item.id,
                    excludingItem: item,
                  )) {
                setModalState(() => isSaving = false);
                if (!ctx.mounted) return;
                FlashySnackBar.show(
                  ctx,
                  message: 'holiday_already_exists'.tr(),
                  isError: true,
                );
                return;
              }

              final holidayId = item.id?.trim() ?? '';
              if (!_isGuest && holidayId.isEmpty) {
                setModalState(() => isSaving = false);
                if (!ctx.mounted) return;
                FlashySnackBar.show(
                  ctx,
                  message: 'unexpected_error'.tr(),
                  isError: true,
                );
                return;
              }

              final dateObj = DateTime(
                calendarDate.year,
                calendarDate.month,
                selectedDay,
              );

              try {
                if (_isGuest) {
                  setState(() {
                    final storageKey = item.storageKey ?? item.month;
                    final oldList = DummyData.holidays[storageKey];
                    Map<String, dynamic>? updatedHoliday;

                    if (oldList != null) {
                      final idx = oldList.indexWhere(
                        (h) => _matchesGuestHoliday(h, item),
                      );
                      if (idx != -1) {
                        updatedHoliday = Map<String, dynamic>.from(
                          oldList[idx],
                        );
                        oldList.removeAt(idx);
                        if (oldList.isEmpty) {
                          DummyData.holidays.remove(storageKey);
                        }
                      }
                    }

                    updatedHoliday ??= {'isEnabled': item.isEnabled};
                    updatedHoliday['name'] = holidayName;
                    updatedHoliday['isRecurring'] = item.isRecurring;
                    updatedHoliday['date'] =
                        '${selectedDay.toString().padLeft(2, '0')}/${calendarDate.month.toString().padLeft(2, '0')}/${calendarDate.year}';

                    DummyData.holidays
                        .putIfAbsent(selectedMonthName, () => [])
                        .insert(0, updatedHoliday);
                    DummyData.saveToPrefs();
                    _holidaysByMonth = _guestHolidayGroups();
                  });
                } else {
                  await _firestore.updateHoliday(holidayId, {
                    'name': holidayName,
                    'date': dateObj,
                    'isRecurring': item.isRecurring,
                  });
                }
              } catch (e) {
                if (!ctx.mounted) return;
                setModalState(() => isSaving = false);
                FlashySnackBar.show(
                  ctx,
                  message: 'failed_to_update_holiday'.tr(
                    namedArgs: {'error': e.toString()},
                  ),
                  isError: true,
                );
                return;
              }

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (mounted) {
                FlashySnackBar.show(context, message: 'holiday_updated'.tr());
              }
            }

            return _buildHolidayDialog(
              parentContext: context,
              dialogTitle: 'edit_holiday'.tr(),
              nameController: nameController,
              selectedDay: selectedDay,
              calendarDate: calendarDate,
              isSaving: isSaving,
              onDaySelected: (day) => setModalState(() => selectedDay = day),
              onMonthChanged: (newDate) {
                setModalState(() {
                  calendarDate = newDate;
                  final maxDay = DateTime(
                    newDate.year,
                    newDate.month + 1,
                    0,
                  ).day;
                  if (selectedDay > maxDay) selectedDay = maxDay;
                });
              },
              onSave: onSave,
              onClose: () => Navigator.of(ctx).pop(),
            );
          },
        );
      },
    ).whenComplete(nameController.dispose);
  }

  Future<void> _deleteHoliday(HolidayItem item) async {
    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_holiday'.tr(),
      content: 'delete_holiday_desc'.tr(),
    );
    if (!confirmed) return;

    if (_isGuest) {
      setState(() {
        final monthList = _holidaysByMonth[item.month];
        if (monthList != null) {
          monthList.removeWhere(
            (h) => h.day == item.day && h.name == item.name,
          );
          if (monthList.isEmpty) _holidaysByMonth.remove(item.month);
        }
      });

      final storageKey = item.storageKey ?? item.month;
      final dummyList = DummyData.holidays[storageKey];
      if (dummyList != null) {
        dummyList.removeWhere((h) => _matchesGuestHoliday(h, item));
        if (dummyList.isEmpty) DummyData.holidays.remove(storageKey);
      }

      await DummyData.saveToPrefs();
      if (mounted) {
        FlashySnackBar.show(context, message: 'holiday_deleted'.tr());
      }
      return;
    }

    final holidayId = item.id?.trim() ?? '';
    if (holidayId.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
      return;
    }

    try {
      await _firestore.deleteHoliday(holidayId);
      if (mounted) {
        FlashySnackBar.show(context, message: 'holiday_deleted'.tr());
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    }
  }

  Widget _buildModalCalendar(
    DateTime calendarDate,
    int? selectedDay,
    ValueChanged<int> onDaySelected,
    ValueChanged<DateTime> onMonthChanged,
  ) {
    return ModalCalendar(
      calendarDate: calendarDate,
      selectedDay: selectedDay,
      onDaySelected: onDaySelected,
      onMonthChanged: onMonthChanged,
      disablePastDays: true,
      disablePastMonths: true,
      allowFutureMonths: true,
      showBorder: false,
      spacing: 10,
      cellAspectRatio: 1.09,
      cellBorderRadius: BorderRadius.circular(4),
      weekdayBorderRadius: const Radius.circular(4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopActionRow(),
                  const SizedBox(height: 16),
                  _buildCompanyWorkDaysSummary(),
                  const SizedBox(height: 24),
                  _buildHolidayListHeader(),
                  const SizedBox(height: 16),
                  _isLoading
                      ? ScreenTableShimmer(
                          height: (MediaQuery.of(context).size.height - 430)
                              .clamp(460.0, 1200.0),
                          columnFlexes: const [3, 2, 2],
                          showLeadingAvatar: false,
                        )
                      : _holidaysByMonth.values.every((l) => l.isEmpty)
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

  Widget _buildHeader() {
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
                style: const TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
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

  Widget _buildTopActionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'work_schedule'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'company_work_days_help'.tr(),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () {
            if (_isGuest) {
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
            'set_workdays'.tr(),
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHolidayListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            'holiday_list'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF000000),
            ),
          ),
        ),
        const SizedBox(width: 16),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ElevatedButton.icon(
            onPressed: () {
              if (_isGuest) {
                if (!mounted) return;
                showGuestRestrictionDialog(context);
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
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyWorkDaysSummary() {
    final workingDays = LocalizationHelper.weekdayKeys.keys
        .where(_companyWorkingDays.contains)
        .map(_weekdayLabel)
        .join(', ');
    final offDays = LocalizationHelper.weekdayKeys.keys
        .where((d) => !_companyWorkingDays.contains(d))
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildFilledState() {
    final months =
        _holidaysByMonth.keys
            .where((m) => _holidaysByMonth[m]!.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final aIdx = _calendarMonths.indexOf(a);
            final bIdx = _calendarMonths.indexOf(b);
            if (aIdx == -1 && bIdx == -1) return a.compareTo(b);
            if (aIdx == -1) return 1;
            if (bIdx == -1) return -1;
            return aIdx.compareTo(bIdx);
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: months
          .map(
            (month) => Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: _buildMonthGroup(month, _holidaysByMonth[month]!),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMonthGroup(String month, List<HolidayItem> holidays) {
    final sorted = List<HolidayItem>.from(holidays)
      ..sort((a, b) {
        final yearCmp = (a.year ?? 0).compareTo(b.year ?? 0);
        if (yearCmp != 0) return yearCmp;
        final dayCmp = a.day.compareTo(b.day);
        if (dayCmp != 0) return dayCmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localizeMonth(month),
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF000000),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...sorted.map(_buildListItem),
      ],
    );
  }

  Widget _buildListItem(HolidayItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
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
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '${LocalizationHelper.localizeHolidayName(item.name)}${item.isRecurring ? ' (Every Year)' : ''}',
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () async {
              final value = !item.isEnabled;
              if (_isGuest) {
                setState(() => item.isEnabled = value);
                final monthList =
                    DummyData.holidays[item.storageKey ?? item.month];
                if (monthList != null) {
                  for (final h in monthList) {
                    if (_matchesGuestHoliday(h, item)) {
                      h['isEnabled'] = value;
                      break;
                    }
                  }
                }
                DummyData.saveToPrefs();
                return;
              }

              final holidayId = item.id?.trim() ?? '';
              if (holidayId.isEmpty ||
                  _updatingHolidayIds.contains(holidayId)) {
                if (holidayId.isEmpty && mounted) {
                  FlashySnackBar.show(
                    context,
                    message: 'unexpected_error'.tr(),
                    isError: true,
                  );
                }
                return;
              }

              setState(() {
                _updatingHolidayIds.add(holidayId);
                item.isEnabled = value;
              });
              try {
                await _firestore.updateHoliday(holidayId, {'isEnabled': value});
              } catch (e) {
                if (mounted) {
                  setState(() => item.isEnabled = !value);
                  FlashySnackBar.show(
                    context,
                    message: 'error_updating_holiday'.tr(
                      namedArgs: {'error': e.toString()},
                    ),
                    isError: true,
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _updatingHolidayIds.remove(holidayId));
                } else {
                  _updatingHolidayIds.remove(holidayId);
                }
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
              color: Color(0xFF000000),
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
              if (_isGuest) {
                showGuestRestrictionDialog(context);
                return;
              }
              if (value == 'edit') {
                _editHoliday(item);
              } else if (value == 'delete') {
                _deleteHoliday(item);
              }
            },
            itemBuilder: (_) => [
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
                        Color(0xFFFF1014),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'delete'.tr(),
                      style: const TextStyle(
                        color: Color(0xFFFF1014),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
    final containerHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
      1200.0,
    );
    return Container(
      width: double.infinity,
      height: containerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/placeholder_workers.svg',
            width: 120,
            height: 100,
            colorFilter: const ColorFilter.mode(
              Color(0xFFCBCBCB),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'no_holidays_found'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0247C4),
              ),
            ),
          ),
        ],
      ),
    );
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
  final String? storageKey;

  HolidayItem(
    this.day,
    this.name,
    this.isEnabled, {
    this.id,
    required this.month,
    this.year,
    this.isRecurring = false,
    this.storageKey,
  });
}
