import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SvgFillColorMapper extends ColorMapper {
  const SvgFillColorMapper({required this.source, required this.replacement});

  final Color source;
  final Color replacement;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    return color == source ? replacement : color;
  }

  @override
  bool operator ==(Object other) =>
      other is SvgFillColorMapper &&
      other.source == source &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(source, replacement);
}
