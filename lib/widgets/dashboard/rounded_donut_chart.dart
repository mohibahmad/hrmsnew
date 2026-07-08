import 'package:flutter/material.dart';

class RoundedDonutChart extends StatelessWidget {
  final double malePercent;
  final double femalePercent;

  const RoundedDonutChart({
    super.key,
    required this.malePercent,
    required this.femalePercent,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$malePercent-$femalePercent'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return CustomPaint(
          size: const Size(135, 135),
          painter: DonutChartPainter(
            progress: value,
            malePercent: malePercent,
            femalePercent: femalePercent,
          ),
        );
      },
    );
  }
}

class DonutChartPainter extends CustomPainter {
  final double progress;
  final double malePercent;
  final double femalePercent;

  DonutChartPainter({
    this.progress = 1,
    required this.malePercent,
    required this.femalePercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;

    final redPaint = Paint()
      ..color = const Color(0xFFFF2D2D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final bluePaint = Paint()
      ..color = const Color(0xFF155ED5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    const double startAngle = -3.1415926535 / 4;
    final double redSweep = femalePercent * 2 * 3.1415926535;
    final double blueSweep = malePercent * 2 * 3.1415926535;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      redSweep * progress,
      false,
      redPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + redSweep * progress,
      blueSweep * progress,
      false,
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.malePercent != malePercent ||
      oldDelegate.femalePercent != femalePercent;
}
