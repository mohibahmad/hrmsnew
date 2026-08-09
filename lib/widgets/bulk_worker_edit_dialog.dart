import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/currency_utils.dart';
import '../utils/localization_helper.dart';
import '../utils/bulk_worker_validator.dart';
import '../utils/snackbar_utils.dart';

String fieldHint(String fieldKey) {
  const hintKeys = <String, String>{
    'name': 'hint_enter_full_name',
    'email': 'hint_enter_email',
    'phone': 'hint_enter_phone',
    'fatherName': 'hint_enter_father_name',
    'nationalId': 'hint_enter_national_id',
    'religion': 'hint_enter_religion',
    'gender': 'hint_enter_gender',
    'dob': 'hint_enter_dob',
    'address': 'hint_enter_address',
    'relationshipStatus': 'hint_enter_relationship',
    'position': 'hint_enter_position',
    'type1': 'hint_enter_type1',
    'type2': 'hint_enter_type2',
    'experienceLevel': 'hint_enter_experience',
    'education': 'hint_enter_education',
    'salaryAmount': 'hint_enter_salary_amount',
    'annualLeaves': 'hint_enter_annual_leaves',
    'sickLeaves': 'hint_enter_sick_leaves',
    'casualLeaves': 'hint_enter_casual_leaves',
    'medicalLeaves': 'hint_enter_medical_leaves',
    'joiningDate': 'hint_enter_joining_date',
    'profileImage': 'hint_enter_profile_image',
    'frontId': 'hint_enter_front_id',
    'backId': 'hint_enter_back_id',
    'cv': 'hint_enter_cv',
  };
  final key = hintKeys[fieldKey];
  return key != null ? key.tr() : '';
}

/// Hint shown *inside* the text field for media (image / file) columns.
String mediaFieldHint(String fieldKey) {
  const hintKeys = <String, String>{
    'profileImage': 'hint_media_profile_image',
    'frontId': 'hint_media_front_id',
    'backId': 'hint_media_back_id',
    'cv': 'hint_media_cv',
  };
  final key = hintKeys[fieldKey];
  return key != null ? key.tr() : '';
}

Widget buildDateField({
  required BuildContext context,
  required String fieldKey,
  required String currentValue,
  required String label,
  required void Function(VoidCallback) setDialogState,
  required void Function(String) onDateSelected,
}) {
  final parsed = parseDate(currentValue);
  final displayText = currentValue.isNotEmpty
      ? currentValue
      : 'Tap to select date';
  final hasError =
      (fieldKey == 'dob' && parsed != null && !isAtLeast18(parsed)) ||
      (fieldKey == 'joiningDate' &&
          parsed != null &&
          parsed.isAfter(DateTime.now()));

  return GestureDetector(
    onTap: () => showCupertinoDatePickerDialog(
      context: context,
      fieldKey: fieldKey,
      label: label,
      currentDate: parsed,
      setDialogState: setDialogState,
      onDateSelected: onDateSelected,
    ),
    child: Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasError ? const Color(0xFFDC2626) : const Color(0xFFD1D5DB),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.calendar,
            size: 18,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                  fontWeight: FontWeight.w500,
                  color: currentValue.isEmpty
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF374151),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void showCupertinoDatePickerDialog({
  required BuildContext context,
  required String fieldKey,
  required String label,
  required DateTime? currentDate,
  required void Function(VoidCallback) setDialogState,
  required void Function(String) onDateSelected,
}) {
  final now = DateTime.now();
  final minimumDate = fieldKey == 'dob' ? DateTime(1920) : DateTime(2000);

  final DateTime maximumDate;
  if (fieldKey == 'dob') {
    maximumDate = DateTime(now.year - 18, now.month, now.day);
  } else {
    maximumDate = now;
  }
  DateTime selected =
      currentDate ?? (fieldKey == 'dob' ? DateTime(2000, 1, 1) : now);
  if (selected.isBefore(minimumDate)) {
    selected = minimumDate;
  }
  if (selected.isAfter(maximumDate)) {
    selected = maximumDate;
  }

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Date Picker',
    barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(
          opacity: anim,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 40,
            ),
            child: Center(
              child: StatefulBuilder(
                builder: (_, setPickerState) {
                  return Container(
                    width: 380,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0247C4,
                          ).withValues(alpha: 0.18),
                          blurRadius: 40,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.calendar,
                                size: 20,
                                color: const Color(0xFF0247C4),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (fieldKey == 'dob')
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_circle,
                                  size: 14,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'worker_must_be_18'.tr(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
                            initialDateTime: selected,
                            minimumDate: minimumDate,
                            maximumDate: maximumDate,
                            onDateTimeChanged: (DateTime newDate) {
                              setPickerState(() {
                                selected = newDate;
                              });
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.of(ctx).pop(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'cancel'.tr(),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF374151),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (fieldKey == 'dob' &&
                                        !isAtLeast18(selected)) {
                                      FlashySnackBar.show(
                                        ctx,
                                        message: 'worker_must_be_18'.tr(),
                                        isError: true,
                                      );
                                      return;
                                    }
                                    if (fieldKey == 'joiningDate' &&
                                        selected.isAfter(DateTime.now())) {
                                      FlashySnackBar.show(
                                        ctx,
                                        message: 'joining_date_cannot_be_future'
                                            .tr(),
                                        isError: true,
                                      );
                                      return;
                                    }
                                    final dateStr = formatDateForField(
                                      selected,
                                    );
                                    onDateSelected(dateStr);
                                    setDialogState(() {});
                                    Navigator.of(ctx).pop();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0247C4),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'done'.tr(),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget buildCurrencyDropdown({
  required String label,
  required TextEditingController controller,
  required void Function(VoidCallback) setDialogState,
}) {
  final currentCode = controller.text.trim().toUpperCase();

  return Container(
    clipBehavior: Clip.hardEdge,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFD1D5DB), width: 1.2),
    ),
    child: PopupMenuButton<String>(
      tooltip: '',
      onSelected: (val) {
        setDialogState(() {
          controller.text = val;
        });
      },
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
      ),
      color: const Color(0xFFFFFFFF),
      elevation: 4,
      itemBuilder: (context) {
        return CurrencyUtils.supportedCodes.map((code) {
          final isSelected = code == currentCode;
          return PopupMenuItem<String>(
            value: code,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: isSelected
                      ? const Color(0xFF0247C4)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    LocalizationHelper.localizeCurrency(code),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? const Color(0xFF0247C4)
                          : const Color(0xFF111827),
                      fontFamily: 'SF Pro Display',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                currentCode.isEmpty
                    ? 'edit_cell_enter_value'.tr(namedArgs: {'label': label})
                    : CurrencyUtils.isSupported(currentCode)
                    ? LocalizationHelper.localizeCurrency(currentCode)
                    : currentCode,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'SF Pro Display',
                  color: const Color(0xFF9CA3AF),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              color: Color(0xFF9CA3AF),
              size: 22,
            ),
          ],
        ),
      ),
    ),
  );
}

List<TextInputFormatter>? inputFormattersForField(String fieldKey) {
  if (fieldKey == 'phone') {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'^[\d+\-\s()]*')),
      LengthLimitingTextInputFormatter(20),
    ];
  }
  if (fieldKey == 'nationalId') {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'^[A-Za-z0-9\-]*')),
      LengthLimitingTextInputFormatter(20),
    ];
  }
  if (fieldKey == 'email') {
    return [LengthLimitingTextInputFormatter(100)];
  }
  if (fieldKey == 'religion') {
    return [LengthLimitingTextInputFormatter(30)];
  }
  if (fieldKey == 'gender') {
    return [LengthLimitingTextInputFormatter(10)];
  }
  if (fieldKey == 'relationshipStatus') {
    return [LengthLimitingTextInputFormatter(10)];
  }
  if (fieldKey == 'name' || fieldKey == 'fatherName') {
    return [LengthLimitingTextInputFormatter(50)];
  }
  if (fieldKey == 'position') {
    return [LengthLimitingTextInputFormatter(60)];
  }
  if (fieldKey == 'type1' ||
      fieldKey == 'type2' ||
      fieldKey == 'experienceLevel' ||
      fieldKey == 'education') {
    return [LengthLimitingTextInputFormatter(50)];
  }
  if (fieldKey == 'address') {
    return [LengthLimitingTextInputFormatter(500)];
  }
  if (fieldKey == 'annualLeaves' ||
      fieldKey == 'sickLeaves' ||
      fieldKey == 'casualLeaves' ||
      fieldKey == 'medicalLeaves') {
    return [
      LengthLimitingTextInputFormatter(3),
      TextInputFormatter.withFunction((oldValue, newValue) {
        if (newValue.text.isEmpty) return newValue;
        final value = int.tryParse(newValue.text);
        if (value == null || value > 366) {
          return oldValue;
        }
        return newValue;
      }),
    ];
  }
  if (fieldKey == 'profileImage' ||
      fieldKey == 'frontId' ||
      fieldKey == 'backId' ||
      fieldKey == 'cv') {
    return [LengthLimitingTextInputFormatter(500)];
  }
  if (fieldKey == 'salaryAmount') {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      TextInputFormatter.withFunction((oldValue, newValue) {
        if (newValue.text.isEmpty) return newValue;
        final parts = newValue.text.split('.');
        final intPart = parts[0];
        // max 12 digits before decimal
        if (intPart.length > 12) return oldValue;
        // max 2 digits after decimal
        if (parts.length > 1 && parts[1].length > 2) return oldValue;
        return newValue;
      }),
    ];
  }
  return null;
}

TextInputType? keyboardTypeForField(String fieldKey) {
  if (fieldKey == 'phone') return TextInputType.phone;
  if (fieldKey == 'email') return TextInputType.emailAddress;
  if (fieldKey == 'salaryAmount') {
    return const TextInputType.numberWithOptions(decimal: true);
  }
  if (fieldKey == 'annualLeaves' ||
      fieldKey == 'sickLeaves' ||
      fieldKey == 'casualLeaves' ||
      fieldKey == 'medicalLeaves') {
    return TextInputType.number;
  }
  if (fieldKey == 'nationalId') {
    return TextInputType.text;
  }
  return null;
}
