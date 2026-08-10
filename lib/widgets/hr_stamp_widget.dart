import 'package:flutter/material.dart';

class HrStampWidget extends StatelessWidget {
  final double size;

  const HrStampWidget({super.key, this.size = 300});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/default_hr_stamp.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
