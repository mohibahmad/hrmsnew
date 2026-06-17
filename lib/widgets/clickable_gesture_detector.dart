import 'package:flutter/gestures.dart' as fm;
import 'package:flutter/material.dart' as fm;

class GestureDetector extends fm.StatelessWidget {
  final fm.Widget? child;
  final fm.GestureTapCallback? onTap;
  final fm.GestureDoubleTapCallback? onDoubleTap;
  final fm.GestureLongPressCallback? onLongPress;
  final fm.GestureTapDownCallback? onTapDown;
  final fm.HitTestBehavior? behavior;

  const GestureDetector({
    super.key,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onTapDown,
    this.behavior,
  });

  @override
  fm.Widget build(fm.BuildContext context) {
    final hasCallback =
        onTap != null || onDoubleTap != null || onLongPress != null || onTapDown != null;
    if (hasCallback) {
      return fm.MouseRegion(
        cursor: fm.SystemMouseCursors.click,
        child: fm.GestureDetector(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          onTapDown: onTapDown,
          behavior: behavior,
          child: child,
        ),
      );
    }
    return fm.GestureDetector(behavior: behavior, child: child);
  }
}
