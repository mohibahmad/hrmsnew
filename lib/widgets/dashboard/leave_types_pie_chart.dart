import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/leave_chart_config.dart';
import '../custom_timeframe_dropdown.dart';

class LeaveTypesPieChart extends StatelessWidget {
  final String period;
  final bool isEmpty;
  final List<Map<String, dynamic>> timeoffDocs;
  final List<Map<String, dynamic>> workersList;

  const LeaveTypesPieChart({
    super.key,
    required this.period,
    this.isEmpty = false,
    required this.timeoffDocs,
    required this.workersList,
  });

  static const Map<String, LeavePeriodConfig> configs = {
    'Week': LeavePeriodConfig(
      casualVal: 60,
      sickVal: 15,
      medicalVal: 25,
      casualPath: [Offset(147, 116), Offset(97, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(230, 110), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    'Month': LeavePeriodConfig(
      casualVal: 50,
      sickVal: 20,
      medicalVal: 30,
      casualPath: [Offset(151, 107.5), Offset(105, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(226.4, 103.5), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    '6 Month': LeavePeriodConfig(
      casualVal: 40,
      sickVal: 30,
      medicalVal: 30,
      casualPath: [Offset(147, 114), Offset(98, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(212, 91), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
    'Yearly': LeavePeriodConfig(
      casualVal: 35,
      sickVal: 35,
      medicalVal: 30,
      casualPath: [Offset(146, 118), Offset(95, 60), Offset(55, 60)],
      casualLeft: 65,
      casualTop: 36,
      sickPath: [Offset(215, 83), Offset(275, 60), Offset(325, 60)],
      sickRight: 65,
      sickTop: 36,
      medicalPath: [Offset(175, 205), Offset(135, 245), Offset(80, 245)],
      medicalLeft: 90,
      medicalBottom: 18,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final defaultConfig = configs[period] ?? configs['Month']!;

    final activeWorkersEmails = workersList
        .map((w) => (w['email'] ?? '').toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final activeWorkersNames = workersList
        .map((w) => (w['name'] ?? '').toString().trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();

    DateTime? dateLimit;
    final now = DateTime.now();
    if (period == 'Week') {
      dateLimit = now.subtract(const Duration(days: 7));
    } else if (period == 'Month') {
      dateLimit = now.subtract(const Duration(days: 30));
    } else if (period == '6 Month') {
      dateLimit = now.subtract(const Duration(days: 180));
    } else if (period == 'Yearly') {
      dateLimit = now.subtract(const Duration(days: 365));
    }

    int casualCount = 0;
    int sickCount = 0;
    int annualCount = 0;

    for (var t in timeoffDocs) {
      final tEmail = (t['email'] ?? '').toString().trim().toLowerCase();
      final tName = (t['name'] ?? '').toString().trim().toLowerCase();
      final belongsToActive =
          (tEmail.isNotEmpty && activeWorkersEmails.contains(tEmail)) ||
          (tName.isNotEmpty && activeWorkersNames.contains(tName));
      if (!belongsToActive) continue;

      if (dateLimit != null) {
        final tDate = DateTime.tryParse(t['startDate'] ?? '');
        if (tDate != null && tDate.isBefore(dateLimit)) {
          continue;
        }
      }

      final action = (t['action'] ?? '').toString().trim().toLowerCase();
      if (action.contains('casual')) {
        casualCount++;
      } else if (action.contains('sick')) {
        sickCount++;
      } else if (action.contains('annual') || action.contains('maternity')) {
        annualCount++;
      } else {
        annualCount++;
      }
    }

    final int total = casualCount + sickCount + annualCount;
    final double casualPercent = total > 0 ? (casualCount / total) * 100 : 0.0;
    final double sickPercent = total > 0 ? (sickCount / total) * 100 : 0.0;
    final double medicalPercent = total > 0 ? (annualCount / total) * 100 : 0.0;

    final double casualVal = total > 0
        ? casualPercent
        : defaultConfig.casualVal;
    final double sickVal = total > 0 ? sickPercent : defaultConfig.sickVal;
    final double medicalVal = total > 0
        ? medicalPercent
        : defaultConfig.medicalVal;

    final double totalValue = casualVal + sickVal + medicalVal;
    final double casualSweep = totalValue > 0
        ? (casualVal / totalValue) * 360
        : 0;
    final double sickSweep = totalValue > 0 ? (sickVal / totalValue) * 360 : 0;
    final double medicalSweep = totalValue > 0
        ? (medicalVal / totalValue) * 360
        : 0;

    double normalizeAngle(double a) {
      double val = a % 360;
      if (val < 0) val += 360;
      return val;
    }

    final double aCasual = normalizeAngle(108 + casualSweep / 2);
    final double aSick = normalizeAngle(108 + casualSweep + sickSweep / 2);
    final double aMedical = normalizeAngle(
      108 + casualSweep + sickSweep + medicalSweep / 2,
    );

    double angleDistance(double a, double b) {
      double diff = (a - b).abs() % 360;
      return diff > 180 ? 360 - diff : diff;
    }

    final slots = [
      const SlotConfig(
        targetAngle: 0.0,
        elbow: Offset(275, 60),
        labelEnd: Offset(325, 60),
        right: 65,
        top: 36,
      ),
      const SlotConfig(
        targetAngle: 120.0,
        elbow: Offset(135, 245),
        labelEnd: Offset(80, 245),
        left: 90,
        bottom: 18,
      ),
      const SlotConfig(
        targetAngle: 240.0,
        elbow: Offset(105, 32),
        labelEnd: Offset(55, 32),
        left: 65,
        top: 8,
      ),
    ];

    final sliceAngles = [aCasual, aSick, aMedical];
    final permutations = const [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];

    double minCost = double.infinity;
    List<int> bestPerm = permutations[0];

    for (final perm in permutations) {
      double cost = 0;
      for (int i = 0; i < 3; i++) {
        cost += angleDistance(sliceAngles[i], slots[perm[i]].targetAngle);
      }
      if (cost < minCost) {
        minCost = cost;
        bestPerm = perm;
      }
    }

    final slotCasual = slots[bestPerm[0]];
    final slotSick = slots[bestPerm[1]];
    final slotMedical = slots[bestPerm[2]];

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

    final double casualStartAngle = 108;
    final double casualEndAngle = 108 + casualSweep;
    final double casualLineAngle = getClosestAngleInSlice(
      casualStartAngle,
      casualEndAngle,
      slotCasual.targetAngle,
      casualSweep * 0.35,
    );

    final double sickStartAngle = casualEndAngle;
    final double sickEndAngle = casualEndAngle + sickSweep;
    final double sickLineAngle = getClosestAngleInSlice(
      sickStartAngle,
      sickEndAngle,
      slotSick.targetAngle,
      sickSweep * 0.35,
    );

    final double medicalStartAngle = sickEndAngle;
    final double medicalEndAngle = sickEndAngle + medicalSweep;
    final double medicalLineAngle = getClosestAngleInSlice(
      medicalStartAngle,
      medicalEndAngle,
      slotMedical.targetAngle,
      medicalSweep * 0.35,
    );

    Offset getCircumferencePoint(double angleDegrees) {
      final double rad = angleDegrees * math.pi / 180;
      return Offset(190 + 45 * math.cos(rad), 130 + 45 * math.sin(rad));
    }

    final config = LeavePeriodConfig(
      casualVal: casualVal,
      sickVal: sickVal,
      medicalVal: medicalVal,
      casualPath: [
        getCircumferencePoint(casualLineAngle),
        slotCasual.elbow,
        slotCasual.labelEnd,
      ],
      sickPath: [
        getCircumferencePoint(sickLineAngle),
        slotSick.elbow,
        slotSick.labelEnd,
      ],
      medicalPath: [
        getCircumferencePoint(medicalLineAngle),
        slotMedical.elbow,
        slotMedical.labelEnd,
      ],
      casualLeft: slotCasual.left,
      casualTop: slotCasual.top,
      casualRight: slotCasual.right,
      casualBottom: slotCasual.bottom,
      sickLeft: slotSick.left,
      sickTop: slotSick.top,
      sickRight: slotSick.right,
      sickBottom: slotSick.bottom,
      medicalLeft: slotMedical.left,
      medicalTop: slotMedical.top,
      medicalRight: slotMedical.right,
      medicalBottom: slotMedical.bottom,
    );

    final bool reallyEmpty = isEmpty || total == 0 || workersList.isEmpty;

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
                                    PieChartSectionData(
                                      color: const Color(0xFF84A9FF),
                                      value: config.casualVal,
                                      radius: 85,
                                      showTitle: false,
                                    ),
                                    PieChartSectionData(
                                      color: const Color(0xFFFF4A5E),
                                      value: config.sickVal,
                                      radius: 85,
                                      showTitle: false,
                                    ),
                                    PieChartSectionData(
                                      color: const Color(0xFF97FFA9),
                                      value: config.medicalVal,
                                      radius: 85,
                                      showTitle: false,
                                    ),
                                  ],
                                ),
                              ),
                              CustomPaint(
                                size: const Size(380, 260),
                                painter: CalloutLinesPainter(
                                  casualPath: config.casualVal > 0
                                      ? config.casualPath
                                      : const [],
                                  sickPath: config.sickVal > 0
                                      ? config.sickPath
                                      : const [],
                                  medicalPath: config.medicalVal > 0
                                      ? config.medicalPath
                                      : const [],
                                ),
                              ),
                              if (config.casualVal > 0)
                                Positioned(
                                  top: config.casualTop,
                                  left: config.casualLeft,
                                  right: config.casualRight,
                                  bottom: config.casualBottom,
                                  child: ChartLabel(
                                    '${config.casualVal.toInt()}%',
                                  ),
                                ),
                              if (config.sickVal > 0)
                                Positioned(
                                  top: config.sickTop,
                                  left: config.sickLeft,
                                  right: config.sickRight,
                                  bottom: config.sickBottom,
                                  child: ChartLabel(
                                    '${config.sickVal.toInt()}%',
                                  ),
                                ),
                              if (config.medicalVal > 0)
                                Positioned(
                                  top: config.medicalTop,
                                  left: config.medicalLeft,
                                  right: config.medicalRight,
                                  bottom: config.medicalBottom,
                                  child: ChartLabel(
                                    '${config.medicalVal.toInt()}%',
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
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: buildLegendItem(
                                const Color(0xFF84A9FF),
                                'casual_leave'.tr(
                                  namedArgs: {
                                    'value': '${config.casualVal.toInt()}',
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: buildLegendItem(
                                const Color(0xFFFF4A5E),
                                'sick_leave'.tr(
                                  namedArgs: {
                                    'value': '${config.sickVal.toInt()}',
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: buildLegendItem(
                                const Color(0xFF97FFA9),
                                'medical_leave'.tr(
                                  namedArgs: {
                                    'value': '${config.medicalVal.toInt()}',
                                  },
                                ),
                              ),
                            ),
                            const Expanded(child: SizedBox()),
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
    );
  }
}

class CalloutLinesPainter extends CustomPainter {
  final List<Offset> casualPath;
  final List<Offset> sickPath;
  final List<Offset> medicalPath;

  CalloutLinesPainter({
    required this.casualPath,
    required this.sickPath,
    required this.medicalPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawOffsetPath(canvas, paint, casualPath);
    _drawOffsetPath(canvas, paint, sickPath);
    _drawOffsetPath(canvas, paint, medicalPath);
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
        oldDelegate.sickPath != sickPath ||
        oldDelegate.medicalPath != medicalPath;
  }
}
