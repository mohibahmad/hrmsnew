import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/common/custom_dropdown_field.dart';

Widget buildInputField(
  String label,
  String hint, {
  IconData? suffixIcon,
  bool isDropdown = false,
  bool isTextArea = false,
  bool isEmail = false,
  bool isAmount = false,
  bool isLeaves = false,
  bool isContact = false,
  bool isNationalId = false,
  bool isReligion = false,
  bool showCurrency = false,
  TextEditingController? controller,
  TextAlign textAlign = TextAlign.start,
  FocusNode? focusNode,
}) {
  final isEmailField = isEmail;
  final isNumeric = isAmount || isLeaves || isContact || isNationalId;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        height: isTextArea ? 90 : 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: isTextArea ? Alignment.topLeft : Alignment.center,
        child: TextField(
          textAlign: textAlign,
          maxLines: isTextArea ? 4 : 1,
          controller: controller,
          focusNode: focusNode,
          keyboardType: isNumeric
              ? (isAmount
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number)
              : null,
          inputFormatters: isNumeric
              ? [
                  FilteringTextInputFormatter.allow(
                    isAmount
                        ? RegExp(r'[\d,.]')
                        : (isNationalId
                              ? RegExp(r'^[A-Za-z0-9\-]*')
                              : isContact
                              ? RegExp(r'[0-9+\-\s()]')
                              : RegExp(r'^\d*')),
                  ),
                  if (isAmount) ...[
                    LengthLimitingTextInputFormatter(18),
                    const ThousandsSeparatorInputFormatter(),
                  ],
                  if (isContact) LengthLimitingTextInputFormatter(20),
                  if (isNationalId) LengthLimitingTextInputFormatter(20),
                  if (isLeaves) ...[
                    LengthLimitingTextInputFormatter(3),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final value = int.tryParse(newValue.text);
                      if (value == null || value > 366) {
                        return oldValue;
                      }
                      return newValue;
                    }),
                  ],
                ]
              : () {
                  final list = <TextInputFormatter>[];
                  if (isEmailField) {
                    list.add(LengthLimitingTextInputFormatter(100));
                  }
                  if (isReligion) {
                    list.add(LengthLimitingTextInputFormatter(30));
                  }
                  return list.isEmpty ? null : list;
                }(),
          style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            border: InputBorder.none,
            isDense: true,
            contentPadding: isTextArea
                ? const EdgeInsets.only(top: 14)
                : const EdgeInsets.symmetric(vertical: 12),
            prefixText: (isAmount && showCurrency)
                ? '${CurrencyUtils.symbolFor(CurrencyUtils.companyCurrency)} | '
                : null,
            prefixStyle: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            suffixIcon: isDropdown
                ? Icon(
                    Icons.arrow_drop_down,
                    color: Colors.grey.shade400,
                    size: 22,
                  )
                : (suffixIcon != null
                      ? Icon(suffixIcon, color: Colors.grey.shade400, size: 22)
                      : null),
          ),
        ),
      ),
    ],
  );
}

Widget buildCustomRadio({
  required String label,
  required bool isSelected,
  required VoidCallback onTap,
}) {
  const selectedColor = Color(0xFF0247C4);
  final borderColor = isSelected ? selectedColor : const Color(0xFF000000);
  final textColor = isSelected ? selectedColor : const Color(0xFF000000);

  return GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
          ),
          child: isSelected
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: selectedColor,
                    ),
                  ),
                )
              : const SizedBox(),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget buildDropdownField({
  required String label,
  required String selectedValue,
  required String hint,
  required List<String> items,
  required ValueChanged<String?> onChanged,
  String? Function(String item)? itemLabelBuilder,
}) {
  return CustomDropdownField(
    label: label,
    selectedValue: selectedValue,
    hint: hint,
    items: items,
    onChanged: onChanged,
    itemLabelBuilder: itemLabelBuilder,
  );
}
