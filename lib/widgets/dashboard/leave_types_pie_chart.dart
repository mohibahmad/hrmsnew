import 'dart:math' as math;
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

    for (final att in attendanceDocs) {
      final status = (att['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'leave') continue;
      final type = (att['type'] ?? '').toString().trim();
      if (type == 'Casual Leave') {
        casualCount++;
      } else if (type == 'Sick Leave') {
        sickCount++;
      }
    }

    final int total = casualCount + sickCount;
    final bool reallyEmpty = isEmpty || total == 0;

    final double casualPercent = total > 0 ? (casualCount / total) * 100 : 0;
    final double sickPercent = total > 0 ? (sickCount / total) * 100 : 0;

    final double casualVal = total > 0 ? casualPercent : 0;
    final double sickVal = total > 0 ? sickPercent : 0;

    final double totalValue = casualVal + sickVal;
    final double casualSweep = totalValue > 0
        ? (casualVal / totalValue) * 360
        : 0;
    final double sickSweep = totalValue > 0
        ? (sickVal / totalValue) * 360
        : 0;

    double normalizeAngle(double a) {
      double val = a % 360;
      if (val < 0) val += 360;
      return val;
    }

    Offset getCircumferencePoint(double angleDegrees) {
      final double rad = angleDegrees * math.pi / 180;
      return Offset(190 + 45 * math.cos(rad), 130 + 45 * math.sin(rad));
    }

    final double casualStartAngle = 108;
    final double casualEndAngle = 108 + casualSweep;
    final double sickStartAngle = casualEndAngle;
    final double sickEndAngle = casualEndAngle + sickSweep;

    double getClosestAngleInSlice(
      double startAngle,
      double endAngle,
      double targetAngle,
      double padding,
    ) {
      double sweep = endAngle - startAngle;
      if (sweep < 0) sweep += 360;
      if (sweep <= 2 * padding) {
        return normalizeAngle(startAngle + sweep / 2);
      }
      double startLimit = startAngle + padding;
      double endLimit = startAngle + sweep - padding;
      double t = (targetAngle - startLimit) % 360;
      if (t < 0) t += 360;
      double allowedSweep = endLimit - startLimit;
      if (t <= allowedSweep) {
        return normalizeAngle(startLimit + t);
      } else {
        double distToStart = 360 - t;
        double distToEnd = t - allowedSweep;
        if (distToStart < distToEnd) {
          return normalizeAngle(startLimit);
        } else {
          return normalizeAngle(endLimit);
        }
      }
    }

    final double casualLineAngle = getClosestAngleInSlice(
      casualStartAngle,
      casualEndAngle,
      0.0,
      casualSweep * 0.35,
    );
    final double sickLineAngle = getClosestAngleInSlice(
      sickStartAngle,
      sickEndAngle,
      120.0,
      sickSweep * 0.35,
    );

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
                      child: TweenAnimationBuilder<double>(
                        key: const ValueKey('entrance'),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutQuart,
                        builder: (context, value, childWidget) {
                          return Opacity(opacity: value, child: childWidget);
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          switchInCurve: Curves.easeInOutCubic,
                          switchOutCurve: Curves.easeInOutCubic,
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                          child: Stack(
                            key: ValueKey(period),
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
                                  ],
                                ),
                              ),
                              CustomPaint(
                                size: const Size(380, 260),
                                painter: CalloutLinesPainter(
                                  casualPath: casualVal > 0
                                      ? [
                                          getCircumferencePoint(casualLineAngle),
                                          casualLineAngle < 180
                                              ? Offset(330, 110)
                                              : Offset(50, 60),
                                          casualLineAngle < 180
                                              ? Offset(370, 110)
                                              : Offset(30, 60),
                                        ]
                                      : const [],
                                  sickPath: sickVal > 0
                                      ? [
                                          getCircumferencePoint(sickLineAngle),
                                          const Offset(135, 245),
                                          const Offset(80, 245),
                                        ]
                                      : const [],
                                ),
                              ),
                              if (casualVal > 0)
                                Positioned(
                                  right: casualLineAngle < 180 ? 40 : null,
                                  left: casualLineAngle < 180 ? null : 40,
                                  top: 42,
                                  child: ChartLabel(
                                    '${casualVal.toInt()}%',
                                  ),
                                ),
                              if (sickVal > 0)
                                Positioned(
                                  left: 90,
                                  bottom: 18,
                                  child: ChartLabel(
                                    '${sickVal.toInt()}%',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: buildLegendItem(
                            const Color(0xFF84A9FF),
                            'casual_leave'.tr(
                              namedArgs: {
                                'value': '${casualVal.toInt()}',
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: buildLegendItem(
                            const Color(0xFFFF4A5E),
                            'sick_leave'.tr(
                              namedArgs: {
                                'value': '${sickVal.toInt()}',
                              },
                            ),
                          ),
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

class ChartLabel extends StatelessWidget {
  final String text;
  const ChartLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class CalloutLinesPainter extends CustomPainter {
  final List<Offset> casualPath;
  final List<Offset> sickPath;

  CalloutLinesPainter({
    required this.casualPath,
    required this.sickPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawOffsetPath(canvas, paint, casualPath);
    _drawOffsetPath(canvas, paint, sickPath);
  }

  void _drawOffsetPath(Canvas canvas, Paint paint, List<Offset> points) {
    if (points.length < 2) return;
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CalloutLinesPainter oldDelegate) {
    return oldDelegate.casualPath != casualPath ||
        oldDelegate.sickPath != sickPath;
  }
}
