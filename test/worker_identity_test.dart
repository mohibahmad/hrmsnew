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

  test('same normalized name is allowed when identity fields differ', () {
    final duplicate = WorkerIdentity.duplicateField(const {
      'name': '  SENIOR   developer ',
      'email': 'different@example.com',
    }, existing);

    expect(duplicate, isNull);
  });

  test('edit duplicate check excludes the current worker ID', () {
    final duplicate = WorkerIdentity.duplicateField(
      existing.first,
      existing,
      excludeId: 'worker-1',
    );

    expect(duplicate, isNull);
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

  test('same frontId URL is not a duplicate', () {
    final duplicate = WorkerIdentity.duplicateField(
      const {
        'name': 'Different Worker',
        'email': 'different@example.com',
        'frontId': ' HTTPS://EXAMPLE.COM/id-card.jpg ',
      },
      const [
        {
          'name': 'Existing Worker',
          'email': 'existing@example.com',
          'frontId': 'https://example.com/id-card.jpg',
        },
      ],
    );

    expect(duplicate, isNull);
  });

  test('same frontId and backId URLs are allowed', () {
    final duplicate = WorkerIdentity.duplicateField(const {
      'name': 'Different Worker',
      'email': 'different@example.com',
      'frontId': 'https://example.com/same-card.jpg',
      'backId': 'https://example.com/same-card.jpg',
    }, const []);

    expect(duplicate, isNull);
  });
}
