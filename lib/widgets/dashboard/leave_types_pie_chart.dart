import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import '../custom_timeframe_dropdown.dart';

class LeaveTypesPieChart extends StatelessWidget {
  final String period;
  final bool isEmpty;
  final List<Map<String, dynamic>> attendanceDocs;

  const LeaveTypesPieChart({
    super.key,
    required this.period,
    this.isEmpty = false,
    required this.attendanceDocs,
  });

  @override
  Widget build(BuildContext context) {
    int casualCount = 0;
    int sickCount = 0;
    int medicalCount = 0;

    for (final att in attendanceDocs) {
      final status = (att['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'leave') continue;
      final type = (att['type'] ?? '').toString().trim();
      if (type == 'Casual Leave') {
        casualCount++;
      } else if (type == 'Sick Leave') {
        sickCount++;
      } else if (type == 'Medical Leave') {
        medicalCount++;
      }
    }

    final int total = casualCount + sickCount + medicalCount;
    final bool reallyEmpty = isEmpty || total == 0;

    final double casualPercent = total > 0 ? (casualCount / total) * 100 : 0;
    final double sickPercent = total > 0 ? (sickCount / total) * 100 : 0;
    final double medicalPercent = total > 0 ? (medicalCount / total) * 100 : 0;

    final double casualVal = total > 0 ? casualPercent : 0;
    final double sickVal = total > 0 ? sickPercent : 0;
    final double medicalVal = total > 0 ? medicalPercent : 0;

    final double totalValue = casualVal + sickVal + medicalVal;
    final double casualSweep = totalValue > 0
        ? (casualVal / totalValue) * 360
        : 0;
    final double sickSweep = totalValue > 0 ? (sickVal / totalValue) * 360 : 0;
    final double medicalSweep = totalValue > 0
        ? (medicalVal / totalValue) * 360
        : 0;

    final double casualStartAngle = 108;
    final double casualMidAngle = casualStartAngle + casualSweep / 2;
    final double sickStartAngle = casualStartAngle + casualSweep;
    final double sickMidAngle = sickStartAngle + sickSweep / 2;
    final double medicalStartAngle = sickStartAngle + sickSweep;
    final double medicalMidAngle = medicalStartAngle + medicalSweep / 2;

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
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                  Center(
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
                              startDegreeOffset: 108,
                              sections: [
                                if (casualVal > 0)
                                  PieChartSectionData(
                                    color: const Color(0xFF84A9FF),
                                    value: casualVal,
                                    radius: 85,
                                    showTitle: false,
                                  ),
                                if (sickVal > 0)
                                  PieChartSectionData(
                                    color: const Color(0xFFFF4A5E),
                                    value: sickVal,
                                    radius: 85,
                                    showTitle: false,
                                  ),
                                if (medicalVal > 0)
                                  PieChartSectionData(
                                    color: const Color(0xFF97FFA9),
                                    value: medicalVal,
                                    radius: 85,
                                    showTitle: false,
                                  ),
                              ],
                            ),
                          ),
                          CustomPaint(
                            size: const Size(380, 260),
                            painter: _DonutCalloutPainter(
                              center: const Offset(190, 130),
                              radius: 85,
                              casualVal: casualVal,
                              sickVal: sickVal,
                              medicalVal: medicalVal,
                              casualMidAngle: casualMidAngle,
                              sickMidAngle: sickMidAngle,
                              medicalMidAngle: medicalMidAngle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: buildLegendItem(
                                const Color(0xFF84A9FF),
                                'casual_leave'.tr(
                                  namedArgs: {'value': '${casualVal.toInt()}'},
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: buildLegendItem(
                                const Color(0xFFFF4A5E),
                                'sick_leave'.tr(
                                  namedArgs: {'value': '${sickVal.toInt()}'},
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: buildLegendItem(
                                const Color(0xFF97FFA9),
                                'medical_leave'.tr(
                                  namedArgs: {'value': '${medicalVal.toInt()}'},
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Spacer(), // Keeps alignment same as above
                          ],
                        ),
                      ],
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
                        'assets/leave_grey.svg',
                        height: 50,
                        width: 50,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'no_leave_data_yet'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
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
              fontFamily: 'SF Pro Display',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DonutCalloutPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double casualVal;
  final double sickVal;
  final double medicalVal;
  final double casualMidAngle;
  final double sickMidAngle;
  final double medicalMidAngle;

  const _DonutCalloutPainter({
    required this.center,
    required this.radius,
    required this.casualVal,
    required this.sickVal,
    required this.medicalVal,
    required this.casualMidAngle,
    required this.sickMidAngle,
    required this.medicalMidAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final leftLabels = <Map<String, dynamic>>[];
    final rightLabels = <Map<String, dynamic>>[];

    void processCallout(String type, double val, double midAngle) {
      if (val <= 0) return;

      final angleRad = midAngle * math.pi / 180.0;
      final innerRadius = radius - 35.0; // Start line deeper inside the slice
      final p1 = Offset(
        center.dx + innerRadius * math.cos(angleRad),
        center.dy + innerRadius * math.sin(angleRad),
      );

      final isRightSide = math.cos(angleRad) >= 0;
      final isTopSide = math.sin(angleRad) < 0;

      final double D =
          55.0; // Increased diagonal extension length to push lines further away
      final double dx = isRightSide ? D : -D;
      final double dy = isTopSide ? -D : D;

      final p2 = Offset(p1.dx + dx, p1.dy + dy);

      if (isRightSide) {
        rightLabels.add({'type': type, 'val': val, 'p1': p1, 'p2': p2});
      } else {
        leftLabels.add({'type': type, 'val': val, 'p1': p1, 'p2': p2});
      }
    }

    processCallout('casual', casualVal, casualMidAngle);
    processCallout('sick', sickVal, sickMidAngle);
    processCallout('medical', medicalVal, medicalMidAngle);

    // Sort labels vertically for anti-collision
    leftLabels.sort(
      (a, b) => (a['p2'] as Offset).dy.compareTo((b['p2'] as Offset).dy),
    );
    rightLabels.sort(
      (a, b) => (a['p2'] as Offset).dy.compareTo((b['p2'] as Offset).dy),
    );

    void drawLabels(List<Map<String, dynamic>> labels, bool isRightSide) {
      final lineExtension = 65.0;
      double lastY = -9999;
      final minSpacing = 35.0; // minimum vertical gap between labels

      for (final labelData in labels) {
        final val = labelData['val'] as double;
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
            text: '${val.toInt()}%',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'SF Pro Display',
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();

        final centerX = (p2.dx + p3.dx) / 2;
        final labelX = centerX - textPainter.width / 2;
        final labelY = p2.dy - textPainter.height - 4; // padding above the line

        textPainter.paint(canvas, Offset(labelX, labelY));
      }
    }

    drawLabels(leftLabels, false);
    drawLabels(rightLabels, true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
