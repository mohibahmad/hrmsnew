import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/navigation_utils.dart';

void main() {
  testWidgets('auth transition supports forward navigation and reverse pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                authTransitionRoute<void>(
                  builder: (destinationContext) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(destinationContext).pop(),
                      child: const Text('Back to Sign In'),
                    ),
                  ),
                ),
              ),
              child: const Text('Forgot Password'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Forgot Password'));
    await tester.pumpAndSettle();
    expect(find.text('Back to Sign In'), findsOneWidget);

    await tester.tap(find.text('Back to Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password'), findsOneWidget);
  });
}
