enum DuplicateWorkerField { name, email, nationalId, frontId, backId }

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
    // The single-worker form historically stores this value when email is
    // optional. It is a placeholder, not a real worker identity.
    return email == 'worker@email.com' ? '' : email;
  }

  static String normalizeNationalId(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '');

  static String normalizeDocumentUrl(dynamic value) =>
      (value ?? '').toString().trim().toLowerCase();

  /// Returns the first identity field that already exists.
  ///
  /// Names are intentionally unique in this HRMS, as requested by the product
  /// flow. Matching ignores capitalization and repeated whitespace.
  static DuplicateWorkerField? duplicateField(
    Map<String, dynamic> candidate,
    Iterable<Map<String, dynamic>> existingWorkers, {
    String? excludeId,
  }) {
    final candidateName = normalizeName(candidate['name']);
    final candidateEmail = normalizeEmail(candidate['email']);
    final candidateNationalId = normalizeNationalId(candidate['nationalId']);
    final candidateFrontId = normalizeDocumentUrl(candidate['frontId']);
    final candidateBackId = normalizeDocumentUrl(candidate['backId']);

    if (candidateFrontId.isNotEmpty && candidateFrontId == candidateBackId) {
      return DuplicateWorkerField.backId;
    }

    for (final existing in existingWorkers) {
      final existingId = (existing['id'] ?? '').toString();
      if (excludeId != null && existingId == excludeId) continue;

      if (candidateName.isNotEmpty &&
          candidateName == normalizeName(existing['name'])) {
        return DuplicateWorkerField.name;
      }
      if (candidateEmail.isNotEmpty &&
          candidateEmail == normalizeEmail(existing['email'])) {
        return DuplicateWorkerField.email;
      }
      if (candidateNationalId.isNotEmpty &&
          candidateNationalId == normalizeNationalId(existing['nationalId'])) {
        return DuplicateWorkerField.nationalId;
      }
      final existingFrontId = normalizeDocumentUrl(existing['frontId']);
      final existingBackId = normalizeDocumentUrl(existing['backId']);
      if (candidateFrontId.isNotEmpty &&
          (candidateFrontId == existingFrontId ||
              candidateFrontId == existingBackId)) {
        return DuplicateWorkerField.frontId;
      }
      if (candidateBackId.isNotEmpty &&
          (candidateBackId == existingFrontId ||
              candidateBackId == existingBackId)) {
        return DuplicateWorkerField.backId;
      }
    }
    return null;
  }
}
