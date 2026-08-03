import 'package:flutter/services.dart';

class CommaCurrencyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    
    final clean = newValue.text.replaceAll(',', '');

    
    if (clean.isEmpty) return const TextEditingValue(text: '');

    
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(clean)) return oldValue;

    
    final dotIdx = clean.indexOf('.');
    final intPart = dotIdx == -1 ? clean : clean.substring(0, dotIdx);
    final decPart = dotIdx == -1 ? '' : clean.substring(dotIdx);

    
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    final formatted = buf.toString() + decPart;

    
    int cleanCursor = 0;
    final cursorLimit =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    for (int i = 0; i < cursorLimit; i++) {
      if (newValue.text[i] != ',') cleanCursor++;
    }

    
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
