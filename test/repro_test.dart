import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/custom_timeframe_dropdown.dart';

void main() {
  testWidgets('dropdown opens on tap and calls onChanged', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CustomTimeframeDropdown(
              selectedPeriod: 'Month',
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('month'));
    await tester.pumpAndSettle();

    expect(find.text('today'), findsOneWidget);

    await tester.tap(find.text('today'));
    await tester.pumpAndSettle();

    expect(selected, 'Today');
  });
}
