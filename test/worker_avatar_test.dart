import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/image_utils.dart';

void main() {
  testWidgets('missing worker image shows the first name letter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkerAvatar(imageUrl: '', name: '  ali khan  '),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.byType(WorkerAvatar), findsOneWidget);
  });
}
