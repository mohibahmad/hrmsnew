import 'package:flutter/material.dart';

InputDecoration buildAuthInputDecoration(
  String hint, {
  bool isPassword = false,
  bool obscureText = false,
  VoidCallback? onToggleVisibility,
  bool hasError = false,
}) {
  final borderColor = hasError ? const Color(0xFFD32F2F) : Colors.grey.shade300;
  final focusedBorderColor = hasError ? const Color(0xFFD32F2F) : const Color(0xFF0044C9);

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 14,
      fontFamily: 'SF Pro Display',
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: focusedBorderColor, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
    ),
    errorStyle: const TextStyle(height: 0, fontSize: 0),
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
        fontFamily: 'SF Pro Display',
      ),
    ),
  );
}

class AuthTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final String hint;
  final bool isPassword;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;

  const AuthTextField({
    super.key,
    this.controller,
    required this.label,
    required this.hint,
    this.isPassword = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.controller?.text ?? '',
      validator: (val) {
        if (widget.validator != null) {
          final actualVal = widget.controller?.text ?? val;
          return widget.validator!(actualVal);
        }
        return null;
      },
      builder: (FormFieldState<String> field) {
        final hasError = field.hasError && field.errorText != null && field.errorText!.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildFieldLabel(widget.label),
            TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              obscureText: widget.isPassword ? _obscureText : false,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              autocorrect: widget.autocorrect,
              enableSuggestions: widget.enableSuggestions,
              onChanged: (val) {
                field.didChange(val);
                if (field.hasError) {
                  field.reset();
                }
              },
              onSubmitted: widget.onFieldSubmitted,
              style: const TextStyle(fontSize: 15, fontFamily: 'SF Pro Display'),
              decoration: buildAuthInputDecoration(
                widget.hint,
                isPassword: widget.isPassword,
                obscureText: _obscureText,
                onToggleVisibility: () {
                  setState(() => _obscureText = !_obscureText);
                },
                hasError: hasError,
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.only(left: 2.0),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(
                    color: Color(0xFFD32F2F),
                    fontSize: 12,
                    fontFamily: 'SF Pro Display',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
