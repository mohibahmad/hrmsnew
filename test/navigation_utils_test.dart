import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/navigation_utils.dart';

void main() {
  test('noTransitionRoute disables forward and reverse animations', () {
    final route = noTransitionRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(route.opaque, isTrue);
  });
}
