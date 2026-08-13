import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_svg/flutter_svg.dart';

class FlashySnackBar {
  static OverlayEntry? _currentEntry;
  static String? _lastMessageKey;
  static DateTime? _lastMessageTime;

  static const Duration _duplicateWindow = Duration(milliseconds: 700);

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    bool isError = false,
    int? maxLines = 3,
    Duration displayDuration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;

    String? routeName;
    if (context.mounted) {
      routeName = ModalRoute.of(context)?.settings.name;
    }
    final messageKey = '$isError:$title:$message:${routeName ?? ''}';
    final now = DateTime.now();
    final isDuplicate =
        _lastMessageKey == messageKey &&
        _lastMessageTime != null &&
        now.difference(_lastMessageTime!) < _duplicateWindow;

    if (isDuplicate) return;

    _lastMessageKey = messageKey;
    _lastMessageTime = now;

    if (_currentEntry != null && _currentEntry!.mounted) {
      _currentEntry!.remove();
    }
    _currentEntry = null;

    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlashySnackBarBody(
        message: message,
        title: title,
        isError: isError,
        maxLines: maxLines,
        onDismiss: () {
          if (entry.mounted) {
            _currentEntry = null;
            entry.remove();
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    Future.delayed(displayDuration, () {
      if (entry.mounted) {
        if (_currentEntry == entry) _currentEntry = null;
        entry.remove();
      }
    });
  }
}

class _FlashySnackBarBody extends StatefulWidget {
  final String message;
  final String? title;
  final bool isError;
  final int? maxLines;
  final VoidCallback onDismiss;

  const _FlashySnackBarBody({
    required this.message,
    this.title,
    required this.isError,
    required this.maxLines,
    required this.onDismiss,
  });

  @override
  State<_FlashySnackBarBody> createState() => _FlashySnackBarBodyState();
}

class _FlashySnackBarBodyState extends State<_FlashySnackBarBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 24,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isError
                        ? [const Color(0xFFFF416C), const Color(0xFFFF4B2B)]
                        : [const Color(0xFF0247C4), const Color(0xFF4A7FE0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (widget.isError
                                  ? const Color(0xFFFF4B2B)
                                  : const Color(0xFF0247C4))
                              .withValues(alpha: 0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: Color(0xFFFFFFFF).withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: widget.isError
                          ? const Icon(
                              Icons.error_outline,
                              color: Color(0xFFFFFFFF),
                              size: 22,
                            )
                          : const Icon(
                              Icons.check_circle_outline,
                              color: Color(0xFFFFFFFF),
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ??
                                (widget.isError
                                    ? 'error_title'.tr()
                                    : 'success'.tr()),
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            softWrap: true,
                            maxLines: widget.maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

PageRoute<T> noTransitionRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

PageRoute<T> authTransitionRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class SvgFillColorMapper extends ColorMapper {
  const SvgFillColorMapper({required this.source, required this.replacement});

  final Color source;
  final Color replacement;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    return color == source ? replacement : color;
  }

  @override
  bool operator ==(Object other) =>
      other is SvgFillColorMapper &&
      other.source == source &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(source, replacement);
}
