import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_constants.dart';

void showLanguageModal(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.05),
    builder: (BuildContext ctx) {
      final allLanguages = languageMap.keys.toList();
      final currentCode = context.locale.languageCode;
      final currentLang = allLanguages.firstWhere(
        (l) => languageMap[l]!.languageCode == currentCode,
        orElse: () => 'English',
      );
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 40.0, top: 96.0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'select_language'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...allLanguages.map((lang) {
                        final isSel = currentLang == lang;
                        return InkWell(
                          onTap: () {
                            context.setLocale(languageMap[lang]!);
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? const Color(0xFFF1F3F5)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  lang,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                if (isSel)
                                  const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Color(0xFF0247C4),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget buildSocialButton({
  required BuildContext context,
  required String text,
  required Widget icon,
  required VoidCallback? onPressed,
  required bool isLoading,
  Color? backgroundColor,
  Color? textColor,
  BorderSide? border,
}) {
  return SizedBox(
    width: double.infinity,
    height: 44,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: backgroundColor ?? Colors.white,
        foregroundColor: textColor ?? const Color(0xFF000000),
        disabledForegroundColor:
            (textColor ?? const Color(0xFF000000)).withValues(alpha: 0.6),
        disabledBackgroundColor: backgroundColor ?? Colors.white,
        side: border ?? BorderSide(color: Colors.grey.shade200),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    textColor ?? const Color(0xFF000000),
                  ),
                ),
              ),
            )
          else
            icon,
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
              color: isLoading
                  ? (textColor ?? const Color(0xFF000000))
                      .withValues(alpha: 0.6)
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
}

class InputLabel extends StatelessWidget {
  final String label;
  const InputLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
        height: 1.0,
      ),
    );
  }
}

InputDecoration inputDecoration(
  String hintText, {
  bool isPassword = false,
  bool obscureText = false,
  VoidCallback? onToggleVisibility,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    suffixIcon: isPassword
        ? Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFFCBCBCB),
                size: 20,
              ),
              onPressed: onToggleVisibility,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          )
        : null,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFF0044C9), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFFFF1014), width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFFFF1014), width: 1.5),
    ),
    errorStyle: const TextStyle(
      color: Color(0xFFFF1014),
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFamily: 'SF Pro Display',
      height: 1.3,
    ),
    errorMaxLines: 2,
  );
}
