import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

const Map<String, Locale> languageMap = {
  'English': Locale('en'),
  'Español': Locale('es'),
  'Français': Locale('fr'),
  'Português': Locale('pt'),
  'Русский': Locale('ru'),
};
const double authHeroTitleLetterSpacing = 2;
const double authHeroSubtitleLetterSpacing = 1.6;
const double authHeroTitleHeight = 105;
const double authHeroSubtitleHeight = 106;

class AuthHeroBanner extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthHeroBanner({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: authHeroTitleHeight,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 88,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFamily: 'SF Pro Display',
                height: 1,
                letterSpacing: authHeroTitleLetterSpacing,
              ),
            ),
          ),
        ),
        SizedBox(
          height: authHeroSubtitleHeight,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(
              subtitle,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'SF Pro Display',
                height: 1.2,
                letterSpacing: authHeroSubtitleLetterSpacing,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void showLanguageModal(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder: (BuildContext ctx) {
      final allLanguages = languageMap.keys.toList();
      final currentCode = context.locale.languageCode;
      final currentLang = allLanguages.firstWhere(
        (l) => languageMap[l]!.languageCode == currentCode,
        orElse: () => 'English',
      );
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 40.0, top: 96.0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
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
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...allLanguages.map((lang) {
                    final isSel = currentLang == lang;
                    return InkWell(
                      onTap: () {
                        ctx.setLocale(languageMap[lang]!);
                        Navigator.pop(ctx);
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
}

Widget buildSocialButton({
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
        disabledForegroundColor: (textColor ?? const Color(0xFF000000))
            .withValues(alpha: 0.6),
        disabledBackgroundColor: backgroundColor ?? Colors.white,
        side: border ?? BorderSide(color: Colors.grey.shade200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              color: isLoading
                  ? (textColor ?? const Color(0xFF000000)).withValues(
                      alpha: 0.6,
                    )
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
        height: 1.0,
      ),
    );
  }
}
