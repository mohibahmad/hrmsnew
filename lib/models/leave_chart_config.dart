import 'package:flutter/material.dart';

class SlotConfig {
  final double targetAngle;
  final Offset elbow;
  final Offset labelEnd;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  const SlotConfig({
    required this.targetAngle,
    required this.elbow,
    required this.labelEnd,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });
}

class LeavePeriodConfig {
  final double casualVal;
  final double sickVal;
  final double medicalVal;

  final List<Offset> casualPath;
  final List<Offset> sickPath;
  final List<Offset> medicalPath;

  final double? casualLeft;
  final double? casualTop;
  final double? casualRight;
  final double? casualBottom;

  final double? sickLeft;
  final double? sickTop;
  final double? sickRight;
  final double? sickBottom;

  final double? medicalLeft;
  final double? medicalTop;
  final double? medicalRight;
  final double? medicalBottom;

  const LeavePeriodConfig({
    required this.casualVal,
    required this.sickVal,
    required this.medicalVal,
    required this.casualPath,
    required this.sickPath,
    required this.medicalPath,
    this.casualLeft,
    this.casualTop,
    this.casualRight,
    this.casualBottom,
    this.sickLeft,
    this.sickTop,
    this.sickRight,
    this.sickBottom,
    this.medicalLeft,
    this.medicalTop,
    this.medicalRight,
    this.medicalBottom,
  });
}
