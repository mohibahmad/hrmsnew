import 'package:flutter/material.dart';

class FlashySnackBar {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    bool isError = false,
  }) {
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

    Future.delayed(const Duration(seconds: 4), () {
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
  final VoidCallback onDismiss;

  const _FlashySnackBarBody({
    required this.message,
    this.title,
    required this.isError,
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
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
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
                width: 380,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isError
                        ? [const Color(0xFFFF416C), const Color(0xFFFF4B2B)]
                        : [const Color(0xFF11998E), const Color(0xFF38EF7D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.isError
                              ? const Color(0xFFFF4B2B)
                              : const Color(0xFF38EF7D))
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: Color(0xFFFFFFFF),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ??
                                (widget.isError ? 'Error' : 'Success'),
                            softWrap: true,
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
                    const SizedBox(width: 32),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 26,
                        ),
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
