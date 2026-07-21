import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/validators.dart';

void main() {
  test('Other is accepted as a worker gender', () {
    expect(
      () => Validators.validateWorker(const {
        'name': 'Alex Worker',
        'gender': 'Other',
      }),
      returnsNormally,
    );
  });
}
