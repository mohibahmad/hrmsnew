import 'package:flutter/material.dart';

import 'app_colors.dart';

InputDecoration buildAuthInputDecoration(
  String hint, {
  bool isPassword = false,
  bool obscureText = false,
  VoidCallback? onToggleVisibility,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: Colors.grey.shade400,
      fontSize: 14,
      fontFamily: AppColors.fontFamily,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF0044C9), width: 1.5),
    ),
    filled: true,
    fillColor: Colors.white,
    suffixIcon: isPassword
        ? IconButton(
            icon: Icon(
              obscureText ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey.shade400,
            ),
            onPressed: onToggleVisibility,
          )
        : null,
  );
}

Widget buildFieldLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6.0),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
        fontFamily: AppColors.fontFamily,
      ),
    ),
  );
}
