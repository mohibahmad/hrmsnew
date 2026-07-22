import 'package:flutter/gestures.dart' as fm;
import 'package:flutter/material.dart' as fm;

class GestureDetector extends fm.StatelessWidget {
  final fm.Widget? child;
  final fm.GestureTapCallback? onTap;
  final fm.GestureDoubleTapCallback? onDoubleTap;
  final fm.GestureLongPressCallback? onLongPress;
  final fm.GestureTapDownCallback? onTapDown;
  final fm.GestureDragDownCallback? onPanDown;
  final fm.GestureDragStartCallback? onPanStart;
  final fm.GestureDragUpdateCallback? onPanUpdate;
  final fm.GestureDragEndCallback? onPanEnd;
  final fm.GestureDragCancelCallback? onPanCancel;
  final fm.DragStartBehavior dragStartBehavior;
  final fm.HitTestBehavior? behavior;

  const GestureDetector({
    super.key,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onTapDown,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.dragStartBehavior = fm.DragStartBehavior.start,
    this.behavior,
  });

  @override
  fm.Widget build(fm.BuildContext context) {
    final hasCallback =
        onTap != null ||
        onDoubleTap != null ||
        onLongPress != null ||
        onTapDown != null ||
        onPanDown != null ||
        onPanStart != null ||
        onPanUpdate != null ||
        onPanEnd != null ||
        onPanCancel != null;
    if (hasCallback) {
      return fm.MouseRegion(
        cursor: fm.SystemMouseCursors.click,
        child: fm.GestureDetector(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          onTapDown: onTapDown,
          onPanDown: onPanDown,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          onPanCancel: onPanCancel,
          dragStartBehavior: dragStartBehavior,
          behavior: behavior,
          child: child,
        ),
      );
    }
    return fm.GestureDetector(behavior: behavior, child: child);
  }
}
