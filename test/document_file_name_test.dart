import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/document_file_name.dart';

void main() {
  test('CV preview preserves underscores from the uploaded filename', () {
    expect(cleanUploadedDocumentFileName('cv_0.pdf'), 'cv_0.pdf');
    expect(
      cleanUploadedDocumentFileName(
        'https://firebasestorage.googleapis.com/v0/b/demo/o/'
        'hrms_documents%2Fcvs%2F1770000000000000_0_Avery_Morgan_CV.pdf'
        '?alt=media&token=test',
      ),
      'Avery_Morgan_CV.pdf',
    );
  });

  test('CV preview preserves legitimate leading numbers', () {
    expect(
      cleanUploadedDocumentFileName('2026_Avery_CV.pdf'),
      '2026_Avery_CV.pdf',
    );
  });
}
