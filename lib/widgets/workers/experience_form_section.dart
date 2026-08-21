import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/workers/worker_form_fields.dart';

final List<String> _months = LocalizationHelper.englishMonthNames.sublist(1);

class ExperienceFormSection extends StatefulWidget {
  final TextEditingController positionController;
  final TextEditingController type1Controller;
  final TextEditingController type2Controller;
  final TextEditingController experienceLevelController;
  final TextEditingController educationController;
  final TextEditingController salaryAmountController;
  final TextEditingController leavePolicyController;
  final TextEditingController annualLeavesController;
  final TextEditingController sickLeavesController;
  final TextEditingController casualLeavesController;
  final TextEditingController medicalLeavesController;
  final String? selectedJoiningDate;
  final ValueChanged<DateTime>? onJoiningDateChanged;
  final VoidCallback? onNextStep;
  final VoidCallback? onPrevStep;

  const ExperienceFormSection({
    super.key,
    required this.positionController,
    required this.type1Controller,
    required this.type2Controller,
    required this.experienceLevelController,
    required this.educationController,
    required this.salaryAmountController,
    required this.leavePolicyController,
    required this.annualLeavesController,
    required this.sickLeavesController,
    required this.casualLeavesController,
    required this.medicalLeavesController,
    this.selectedJoiningDate,
    this.onJoiningDateChanged,
    this.onNextStep,
    this.onPrevStep,
  });

  @override
  State<ExperienceFormSection> createState() => _ExperienceFormSectionState();
}

class _ExperienceFormSectionState extends State<ExperienceFormSection> {
  final Color formBgGrey = const Color(0xFFF2F3F6);
  late DateTime _calendarMonth;
  DateTime? _selectedDate;
  bool _dependenciesReady = false;
  final FocusNode _salaryFocusNode = FocusNode();
  bool _salaryFocused = false;

  bool get _showSalaryCurrency {
    return _salaryFocused ||
        widget.salaryAmountController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _parseSelectedDate();
    _salaryFocusNode.addListener(_onSalaryFocusChange);
    widget.salaryAmountController.addListener(_onSalaryValueChanged);
  }

  void _onSalaryFocusChange() {
    setState(() {
      _salaryFocused = _salaryFocusNode.hasFocus;
    });
  }

  void _onSalaryValueChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _salaryFocusNode.removeListener(_onSalaryFocusChange);
    widget.salaryAmountController.removeListener(_onSalaryValueChanged);
    _salaryFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _dependenciesReady = true;
    _parseSelectedDate(includeLocalizedMonth: true);
  }

  @override
  void didUpdateWidget(covariant ExperienceFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedJoiningDate != oldWidget.selectedJoiningDate) {
      _parseSelectedDate(includeLocalizedMonth: true);
    }
  }

  void _parseSelectedDate({bool includeLocalizedMonth = false}) {
    final dateStr = widget.selectedJoiningDate?.trim() ?? '';
    DateTime? parsedDate;

    if (dateStr.isNotEmpty) {
      parsedDate =
          AppDateUtils.parseDdMmYyyy(dateStr) ??
          AppDateUtils.parseDateString(dateStr);

      if (parsedDate == null) {
        final normalized = dateStr.replaceAll(',', '').trim();
        final parts = normalized.split(RegExp(r'\s+'));
        if (parts.length == 3) {
          final day = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          final englishMonthIndex = _months.indexWhere(
            (month) => month.toLowerCase() == parts[0].toLowerCase(),
          );
          final localizedMonthIndex = includeLocalizedMonth
              ? List<int>.generate(12, (index) => index + 1).indexWhere(
                  (month) =>
                      DateFormat(
                        'MMMM',
                        context.locale.toString(),
                      ).format(DateTime(2000, month)).toLowerCase() ==
                      parts[0].toLowerCase(),
                )
              : -1;
          final monthIndex = englishMonthIndex >= 0
              ? englishMonthIndex
              : localizedMonthIndex;
          if (day != null &&
              year != null &&
              monthIndex >= 0 &&
              day >= 1 &&
              day <= DateTime(year, monthIndex + 2, 0).day) {
            parsedDate = DateTime(year, monthIndex + 1, day);
          }
        }
      }
    }

    _selectedDate = parsedDate == null
        ? null
        : DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
    _calendarMonth = parsedDate == null
        ? DateTime(DateTime.now().year, DateTime.now().month, 1)
        : DateTime(parsedDate.year, parsedDate.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'job_experience_info'.tr(),
              style: const TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onPrevStep != null) ...[
                  GestureDetector(
                    onTap: widget.onPrevStep,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FD),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFE0E0E0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: Color(0xFF000000),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'previous_step'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                GestureDetector(
                  onTap: widget.onNextStep,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9FD),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFE0E0E0),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'next_step'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF000000),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: Color(0xFF000000),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'job_position_label'.tr(),
                            'enter_job_position'.tr(),
                            controller: widget.positionController,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildDropdownField(
                            label: 'experience_level_label'.tr(),
                            selectedValue:
                                widget.experienceLevelController.text,
                            hint: 'enter_your_level'.tr(),
                            items: const [
                              'Fresher',
                              'Junior',
                              'Mid-Level',
                              'Senior',
                            ],
                            itemLabelBuilder: (val) =>
                                LocalizationHelper.localizeExperience(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.experienceLevelController.text = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: buildDropdownField(
                            label: 'work_type_label'.tr(),
                            selectedValue: widget.type1Controller.text,
                            hint: 'enter_your_work'.tr(),
                            items: const [
                              'Full-Time',
                              'Part-Time',
                              'Contract',
                              'Freelance',
                            ],
                            itemLabelBuilder: (val) =>
                                LocalizationHelper.localizeType1(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.type1Controller.text = val;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildDropdownField(
                            label: 'education_label'.tr(),
                            selectedValue: widget.educationController.text,
                            hint: 'enter_your_education'.tr(),
                            items: const [
                              'Matric',
                              'Intermediate',
                              'Bachelor',
                              'Master',
                              'Other',
                            ],
                            itemLabelBuilder: (val) =>
                                LocalizationHelper.localizeEducation(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.educationController.text = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: buildDropdownField(
                            label: 'attendance_type_label'.tr(),
                            selectedValue: widget.type2Controller.text,
                            hint: 'enter_your_attendance_type'.tr(),
                            items: const ['On-Site', 'Remote', 'Hybrid'],
                            itemLabelBuilder: (val) =>
                                LocalizationHelper.localizeType2(val),
                            onChanged: (val) {
                              if (val != null) {
                                widget.type2Controller.text = val;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),

            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'joining_date_set'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF000000,
                          ).withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
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
                                Icons.keyboard_arrow_left,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Flexible(
                              child: Text(
                                '${DateFormat('MMMM', context.locale.toString()).format(_calendarMonth).toUpperCase()} ${_calendarMonth.year}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  letterSpacing: 1.0,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 20),
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
                                Icons.keyboard_arrow_right,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDayPill('weekday_sun'.tr(), true),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_mon'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_tue'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_wed'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_thu'.tr(), false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill(
                                'weekday_fri'.tr(),
                                false,
                                isGreen: true,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildDayPill('weekday_sat'.tr(), false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Builder(
                          builder: (context) {
                            final firstDay = DateTime(
                              _calendarMonth.year,
                              _calendarMonth.month,
                              1,
                            );
                            final firstWeekday = firstDay.weekday;
                            final daysInMonth = DateTime(
                              _calendarMonth.year,
                              _calendarMonth.month + 1,
                              0,
                            ).day;
                            final padCount = firstWeekday == 7
                                ? 0
                                : firstWeekday;
                            final trailingPadCount =
                                42 - (padCount + daysInMonth);

                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 7,
                              mainAxisExtent: 28,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 4,
                              children: [
                                for (int i = 0; i < padCount; i++)
                                  const SizedBox.shrink(),
                                for (int day = 1; day <= daysInMonth; day++)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      final selected = DateTime(
                                        _calendarMonth.year,
                                        _calendarMonth.month,
                                        day,
                                      );
                                      final now = DateTime.now();
                                      final today = DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      );
                                      if (selected.isAfter(today)) {
                                        FlashySnackBar.show(
                                          context,
                                          message:
                                              'joining_date_cannot_be_future'
                                                  .tr(),
                                          isError: true,
                                        );
                                        return;
                                      }
                                      final monthName =
                                          LocalizationHelper.localizedMonth(
                                            selected.month,
                                          );
                                      final formatted =
                                          '$monthName ${selected.day}, ${selected.year}';
                                      widget.onJoiningDateChanged?.call(
                                        selected,
                                      );
                                      setState(() {
                                        _selectedDate = selected;
                                      });
                                      FlashySnackBar.show(
                                        context,
                                        message: 'joining_date_is'.tr(
                                          namedArgs: {'date': formatted},
                                        ),
                                        isError: false,
                                      );
                                    },
                                    child: Builder(
                                      builder: (context) {
                                        final isSelected =
                                            _selectedDate != null &&
                                            _selectedDate!.year ==
                                                _calendarMonth.year &&
                                            _selectedDate!.month ==
                                                _calendarMonth.month &&
                                            _selectedDate!.day == day;
                                        final cellDate = DateTime(
                                          _calendarMonth.year,
                                          _calendarMonth.month,
                                          day,
                                        );
                                        final isSunday = cellDate.weekday == 7;
                                        final isFriday = cellDate.weekday == 5;
                                        final dayColor = isSunday
                                            ? const Color(0xFFFF0004)
                                            : (isFriday
                                                  ? const Color(0xFF4AC000)
                                                  : Colors.black);
                                        final selectedBg = isFriday
                                            ? const Color(0xFF4AC000)
                                            : const Color(0xFF0B50C3);
                                        return Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? selectedBg
                                                : const Color(0xFFFFFFFF),
                                            border: isSelected
                                                ? null
                                                : Border.all(
                                                    color: isSunday
                                                        ? const Color(
                                                            0xFFFF0004,
                                                          ).withValues(
                                                            alpha: 0.4,
                                                          )
                                                        : (isFriday
                                                              ? const Color(
                                                                  0xFF4AC000,
                                                                ).withValues(
                                                                  alpha: 0.4,
                                                                )
                                                              : Colors
                                                                    .grey
                                                                    .shade300),
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '$day',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isSelected
                                                  ? const Color(0xFFFFFFFF)
                                                  : dayColor,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                for (int i = 0; i < trailingPadCount; i++)
                                  const SizedBox.shrink(),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Text(
          'salary_section'.tr(),
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: formBgGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'annual_leaves_days'.tr(),
                            '0',
                            controller: widget.annualLeavesController,
                            isLeaves: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildInputField(
                            'monthly_salary'.tr(),
                            'enter_your_amount'.tr(),
                            controller: widget.salaryAmountController,
                            isAmount: true,
                            showCurrency: _showSalaryCurrency,
                            focusNode: _salaryFocusNode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'sick_leaves_days'.tr(),
                            '0',
                            controller: widget.sickLeavesController,
                            isLeaves: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: buildInputField(
                            'casual_leaves_days'.tr(),
                            '0',
                            controller: widget.casualLeavesController,
                            isLeaves: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: buildInputField(
                            'medical_leaves_days'.tr(),
                            '0',
                            controller: widget.medicalLeavesController,
                            isLeaves: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            const Expanded(flex: 2, child: SizedBox()),
          ],
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildDayPill(String text, bool isRed, {bool isGreen = false}) {
    Color bg = isRed
        ? const Color(0xFFFF1014)
        : (isGreen ? Colors.green : const Color(0xFF0B50C3));
    final display = text.length > 3 ? text.substring(0, 3) : text;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        display,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
