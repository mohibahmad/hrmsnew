import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ScreenSearchShimmer extends StatelessWidget {
  final double height;

  const ScreenSearchShimmer({super.key, this.height = 50});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Shimmer.fromColors(
          baseColor: const Color(0xFFE5E7EB),
          highlightColor: const Color(0xFFF3F4F6),
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
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFFE5E7EB),
            highlightColor: const Color(0xFFF3F4F6),
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
