import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/worker_identity.dart';

void main() {
  const existing = [
    {
      'id': 'worker-1',
      'name': 'Senior Developer',
      'email': 'senior@example.com',
      'nationalId': '12345-6789012-3',
    },
  ];

  test('same normalized name is duplicate even with a different email', () {
    final duplicate = WorkerIdentity.duplicateField(const {
      'name': '  SENIOR   developer ',
      'email': 'different@example.com',
    }, existing);

    expect(duplicate, DuplicateWorkerField.name);
  });

  test('same email is duplicate when name differs', () {
    final duplicate = WorkerIdentity.duplicateField(const {
      'name': 'Different Name',
      'email': 'SENIOR@example.com',
    }, existing);

    expect(duplicate, DuplicateWorkerField.email);
  });

  test('formatted and unformatted National IDs are duplicates', () {
    final duplicate = WorkerIdentity.duplicateField(const {
      'name': 'Different Name',
      'nationalId': '1234567890123',
    }, existing);

    expect(duplicate, DuplicateWorkerField.nationalId);
  });

  test('ignores the legacy optional-email placeholder', () {
    final duplicate = WorkerIdentity.duplicateField(
      const {'name': 'Second Worker', 'email': 'worker@email.com'},
      const [
        {'name': 'First Worker', 'email': 'worker@email.com'},
      ],
    );

    expect(duplicate, isNull);
  });

  test('detects a reused front ID card image', () {
    final duplicate = WorkerIdentity.duplicateField(
      const {
        'name': 'Different Worker',
        'frontId': ' HTTPS://EXAMPLE.COM/id-card.jpg ',
      },
      const [
        {
          'name': 'Existing Worker',
          'frontId': 'https://example.com/id-card.jpg',
        },
      ],
    );

    expect(duplicate, DuplicateWorkerField.frontId);
  });

  test('front and back ID images cannot be the same', () {
    final duplicate = WorkerIdentity.duplicateField(const {
      'name': 'Different Worker',
      'frontId': 'https://example.com/same-card.jpg',
      'backId': 'https://example.com/same-card.jpg',
    }, const []);

    expect(duplicate, DuplicateWorkerField.backId);
  });
}
