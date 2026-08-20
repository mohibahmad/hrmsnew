import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

const screenShimmerPeriod = Duration(milliseconds: 2300);
const screenShimmerBaseColor = Color(0xFFE6E9EE);
const screenShimmerHighlightColor = Color(0xFFFAFBFC);

class DelayedShimmer extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration fadeDuration;

  const DelayedShimmer({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
    this.fadeDuration = const Duration(milliseconds: 220),
  });

  @override
  State<DelayedShimmer> createState() => _DelayedShimmerState();
}

class _DelayedShimmerState extends State<DelayedShimmer> {
  Timer? _timer;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant DelayedShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay != widget.delay) {
      _timer?.cancel();
      _isVisible = false;
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _isVisible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1 : 0,
      duration: widget.fadeDuration,
      curve: Curves.easeOutCubic,
      child: widget.child,
    );
  }
}

class ScreenSearchShimmer extends StatelessWidget {
  final double height;

  const ScreenSearchShimmer({super.key, this.height = 50});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: DelayedShimmer(
          child: Shimmer.fromColors(
            baseColor: screenShimmerBaseColor,
            highlightColor: screenShimmerHighlightColor,
            period: screenShimmerPeriod,
            direction: ShimmerDirection.ltr,
            child: Container(
              height: height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight, reusable loading skeleton for list and table-based screens.
class ScreenTableShimmer extends StatelessWidget {
  final double height;
  final List<int> columnFlexes;
  final int rowCount;
  final bool showHeader;
  final bool showLeadingAvatar;
  final bool showTrailingAction;

  const ScreenTableShimmer({
    super.key,
    required this.height,
    this.columnFlexes = const <int>[3, 2, 2, 2],
    this.rowCount = 6,
    this.showHeader = true,
    this.showLeadingAvatar = true,
    this.showTrailingAction = true,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: DelayedShimmer(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Shimmer.fromColors(
              baseColor: screenShimmerBaseColor,
              highlightColor: screenShimmerHighlightColor,
              period: screenShimmerPeriod,
              direction: ShimmerDirection.ltr,
              child: Column(
                children: [
                  if (showHeader) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < columnFlexes.length;
                            index++
                          )
                            Expanded(
                              flex: columnFlexes[index],
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _ShimmerBlock(
                                  width: index == 0 ? 118 : 82,
                                  height: 15,
                                ),
                              ),
                            ),
                          if (showTrailingAction) const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 1,
                      child: ColoredBox(color: Color(0xFFF7F8FC)),
                    ),
                  ],
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rowCount,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, rowIndex) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FA),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            for (
                              var index = 0;
                              index < columnFlexes.length;
                              index++
                            )
                              Expanded(
                                flex: columnFlexes[index],
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: index == columnFlexes.length - 1
                                        ? 0
                                        : 20,
                                  ),
                                  child: index == 0 && showLeadingAvatar
                                      ? const Row(
                                          children: [
                                            _ShimmerBlock(
                                              width: 40,
                                              height: 40,
                                              radius: 20,
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _ShimmerBlock(
                                                    width: 108,
                                                    height: 14,
                                                  ),
                                                  SizedBox(height: 7),
                                                  _ShimmerBlock(
                                                    width: 142,
                                                    height: 10,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : Align(
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            widthFactor: index.isEven
                                                ? 0.68
                                                : 0.52,
                                            child: const _ShimmerBlock(
                                              width: double.infinity,
                                              height: 14,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            if (showTrailingAction) ...[
                              const SizedBox(width: 16),
                              const _ShimmerBlock(
                                width: 24,
                                height: 24,
                                radius: 6,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBlock({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
