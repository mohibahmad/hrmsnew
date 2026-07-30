enum DuplicateWorkerField { name, email, nationalId }

class DuplicateWorkerException implements Exception {
  final DuplicateWorkerField field;

  const DuplicateWorkerException(this.field);

  @override
  String toString() => 'DuplicateWorkerException: ${field.name}';
}

class WorkerIdentity {
  WorkerIdentity._();

  static String normalizeName(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String normalizeEmail(dynamic value) {
    final email = (value ?? '').toString().trim().toLowerCase();

    return email == 'worker@email.com' ? '' : email;
  }

  static String normalizeNationalId(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '');

  static DuplicateWorkerField? duplicateField(
    Map<String, dynamic> candidate,
    Iterable<Map<String, dynamic>> existingWorkers, {
    String? excludeId,
  }) {
    final candidateEmail = normalizeEmail(candidate['email']);
    final candidateNationalId = normalizeNationalId(candidate['nationalId']);

    for (final existing in existingWorkers) {
      final existingId = (existing['id'] ?? '').toString();
      if (excludeId != null && existingId == excludeId) continue;

      if (candidateEmail.isNotEmpty &&
          candidateEmail == normalizeEmail(existing['email'])) {
        return DuplicateWorkerField.email;
      }
      if (candidateNationalId.isNotEmpty &&
          candidateNationalId == normalizeNationalId(existing['nationalId'])) {
        return DuplicateWorkerField.nationalId;
      }
    }
    return null;
  }
}
