import 'package:flutter/services.dart';

class CommaCurrencyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove existing commas
    final clean = newValue.text.replaceAll(',', '');

    // Allow empty field
    if (clean.isEmpty) return const TextEditingValue(text: '');

    // Validate: only digits and optional single decimal point (max 2 decimal places)
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(clean)) return oldValue;

    // Split into integer and decimal parts
    final dotIdx = clean.indexOf('.');
    final intPart = dotIdx == -1 ? clean : clean.substring(0, dotIdx);
    final decPart = dotIdx == -1 ? '' : clean.substring(dotIdx);

    // Format integer part with commas
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    final formatted = buf.toString() + decPart;

    // Calculate clean (non-comma) cursor position from the new raw input
    int cleanCursor = 0;
    final cursorLimit =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    for (int i = 0; i < cursorLimit; i++) {
      if (newValue.text[i] != ',') cleanCursor++;
    }

    // Map clean cursor position to formatted text position
    int newPos = 0;
    int cleanCount = 0;
    for (int i = 0; i < formatted.length && cleanCount < cleanCursor; i++) {
      newPos++;
      if (formatted[i] != ',') cleanCount++;
    }
    newPos = newPos.clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newPos),
    );
  }
}
