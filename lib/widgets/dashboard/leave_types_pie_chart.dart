import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import '../custom_timeframe_dropdown.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';

const _knownTypeColors = <String, Color>{
  'Casual Leave': Color(0xFF84A9FF),
  'Sick Leave': Color(0xFFFF4A5E),
  'Medical Leave': Color(0xFF97FFA9),
  'Annual Leave': Color(0xFFFFC857),
};

const _fallbackPalette = <Color>[
  Color(0xFF60A5FA),
  Color(0xFFF87171),
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
  Color(0xFFF472B6),
  Color(0xFF38BDF8),
  Color(0xFFFF8C69),
];

const double _pieRadius = 90;

class LeaveTypesPieChart extends StatelessWidget {
  final String period;
  final bool isEmpty;
  final List<Map<String, dynamic>> leaveDocs;

  const LeaveTypesPieChart({
    super.key,
    required this.period,
    this.isEmpty = false,
    required this.leaveDocs,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final att in leaveDocs) {
      final status = (att['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'leave') continue;
      final type = (att['type'] ?? '').toString().trim();
      if (type.isEmpty) continue;
      counts[type] = (counts[type] ?? 0) + 1;
    }

    final int total = counts.values.fold(0, (s, v) => s + v);
    final bool reallyEmpty = isEmpty || total == 0;

    final sortedTypes = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    int fallbackIdx = 0;
    final typeColors = <String, Color>{};
    for (final entry in sortedTypes) {
      typeColors[entry.key] =
          _knownTypeColors[entry.key] ??
          _fallbackPalette[fallbackIdx++ % _fallbackPalette.length];
    }

    final typePercents = <String, double>{};
    for (final entry in sortedTypes) {
      typePercents[entry.key] = (entry.value / total) * 100;
    }
    final displayPercents = calculateRoundedLeavePercentages(
      sortedTypes,
      total,
    );

    const double startAngle = 108;
    final sweeps = <String, double>{};
    for (final entry in sortedTypes) {
      sweeps[entry.key] = (typePercents[entry.key]! / 100) * 360;
    }

    final midAngles = <String, double>{};
    double runningAngle = startAngle;
    for (final entry in sortedTypes) {
      final sweep = sweeps[entry.key]!;
      midAngles[entry.key] = runningAngle + sweep / 2;
      runningAngle += sweep;
    }

    return Card(
      elevation: 0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: !reallyEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CustomTimeframeDropdown.localizePeriod(period),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 380,
                        height: 260,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                sectionsSpace: 0.0,
                                centerSpaceRadius: 0,
                                startDegreeOffset: startAngle,
                                sections: [
                                  for (final entry in sortedTypes)
                                    PieChartSectionData(
                                      color: typeColors[entry.key]!,
                                      value: typePercents[entry.key]!,
                                      radius: _pieRadius,
                                      showTitle: false,
                                    ),
                                ],
                              ),
                            ),
                            CustomPaint(
                              size: const Size(380, 260),
                              painter: _DynamicCalloutPainter(
                                center: const Offset(190, 130),
                                radius: _pieRadius,
                                entries: [
                                  for (final entry in sortedTypes)
                                    _CalloutEntry(
                                      percent: typePercents[entry.key]!,
                                      displayPercent:
                                          displayPercents[entry.key]!,
                                      midAngle: midAngles[entry.key]!,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _buildLegend(
                      sortedTypes,
                      typeColors,
                      displayPercents,
                    ),
                  ),
                ],
              )
            : SizedBox(
                height: 430,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/leave.svg',
                        height: 50,
                        width: 50,
                        colorMapper: const SvgFillColorMapper(
                          source: Color(0xFFFF7B00),
                          replacement: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'no_leave_data_yet'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLegend(
    List<MapEntry<String, int>> sortedTypes,
    Map<String, Color> typeColors,
    Map<String, int> displayPercents,
  ) {
    final rows = <Widget>[];
    for (int i = 0; i < sortedTypes.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 12));
      final rowItems = <Widget>[];

      final first = sortedTypes[i];
      rowItems.add(
        Expanded(
          child: buildLegendItem(
            typeColors[first.key]!,
            '${LocalizationHelper.localizeLeaveType(first.key)}: '
            '${displayPercents[first.key]}%',
          ),
        ),
      );

      if (i + 1 < sortedTypes.length) {
        final second = sortedTypes[i + 1];
        rowItems.add(const SizedBox(width: 16));
        rowItems.add(
          Expanded(
            child: buildLegendItem(
              typeColors[second.key]!,
              '${LocalizationHelper.localizeLeaveType(second.key)}: '
              '${displayPercents[second.key]}%',
            ),
          ),
        );
      }

      rows.add(Row(children: rowItems));
    }
    return Column(children: rows);
  }

  static Widget buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF000000),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

Map<String, int> calculateRoundedLeavePercentages(
  List<MapEntry<String, int>> entries,
  int total,
) {
  if (entries.isEmpty || total <= 0) return const {};

  final percentages = <String, int>{};
  final remainders = <({String type, double remainder, int index})>[];
  var allocated = 0;

  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final exact = entry.value * 100 / total;
    final roundedDown = exact.floor();
    percentages[entry.key] = roundedDown;
    allocated += roundedDown;
    remainders.add((
      type: entry.key,
      remainder: exact - roundedDown,
      index: index,
    ));
  }

  remainders.sort((a, b) {
    final byRemainder = b.remainder.compareTo(a.remainder);
    return byRemainder != 0 ? byRemainder : a.index.compareTo(b.index);
  });

  for (var index = 0; index < 100 - allocated; index++) {
    final type = remainders[index].type;
    percentages[type] = percentages[type]! + 1;
  }

  return percentages;
}

class _CalloutEntry {
  final double percent;
  final int displayPercent;
  final double midAngle;
  const _CalloutEntry({
    required this.percent,
    required this.displayPercent,
    required this.midAngle,
  });
}

class _DynamicCalloutPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final List<_CalloutEntry> entries;

  const _DynamicCalloutPainter({
    required this.center,
    required this.radius,
    required this.entries,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final leftLabels = <Map<String, dynamic>>[];
    final rightLabels = <Map<String, dynamic>>[];

    for (final entry in entries) {
      if (entry.percent <= 0) continue;

      final angleRad = entry.midAngle * math.pi / 180.0;
      final innerRadius = radius - 35.0;
      final p1 = Offset(
        center.dx + innerRadius * math.cos(angleRad),
        center.dy + innerRadius * math.sin(angleRad),
      );

      final isRightSide = math.cos(angleRad) >= 0;
      final isTopSide = math.sin(angleRad) < 0;

      const double D = 55.0;
      final double dx = isRightSide ? D : -D;
      final double dy = isTopSide ? -D : D;

      final p2 = Offset(p1.dx + dx, p1.dy + dy);

      if (isRightSide) {
        rightLabels.add({'entry': entry, 'p1': p1, 'p2': p2});
      } else {
        leftLabels.add({'entry': entry, 'p1': p1, 'p2': p2});
      }
    }

    leftLabels.sort(
      (a, b) => (a['p2'] as Offset).dy.compareTo((b['p2'] as Offset).dy),
    );
    rightLabels.sort(
      (a, b) => (a['p2'] as Offset).dy.compareTo((b['p2'] as Offset).dy),
    );

    void drawLabels(List<Map<String, dynamic>> labels, bool isRightSide) {
      const lineExtension = 65.0;
      double lastY = -9999;
      const minSpacing = 35.0;

      for (final labelData in labels) {
        final entry = labelData['entry'] as _CalloutEntry;
        final p1 = labelData['p1'] as Offset;
        var p2 = labelData['p2'] as Offset;

        if (p2.dy < lastY + minSpacing) {
          p2 = Offset(p2.dx, lastY + minSpacing);
        }
        lastY = p2.dy;

        final p3 = Offset(
          p2.dx + (isRightSide ? lineExtension : -lineExtension),
          p2.dy,
        );

        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy);
        canvas.drawPath(path, linePaint);

        final textPainter = TextPainter(
          text: TextSpan(
            text: '${entry.displayPercent}%',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();

        final centerX = (p2.dx + p3.dx) / 2;
        final labelX = centerX - textPainter.width / 2;
        final labelY = p2.dy - textPainter.height - 4;

        textPainter.paint(canvas, Offset(labelX, labelY));
      }
    }

    drawLabels(leftLabels, false);
    drawLabels(rightLabels, true);
  }

  @override
  bool shouldRepaint(covariant _DynamicCalloutPainter oldDelegate) {
    if (entries.length != oldDelegate.entries.length) return true;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].percent != oldDelegate.entries[i].percent ||
          entries[i].displayPercent != oldDelegate.entries[i].displayPercent ||
          entries[i].midAngle != oldDelegate.entries[i].midAngle) {
        return true;
      }
    }
    return false;
  }
}
