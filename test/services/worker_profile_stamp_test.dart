import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/worker_profile_service.dart';
import 'package:image/image.dart' as img;

import '../helpers/localization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List makePng({int size = 64, int r = 200, int g = 30, int b = 30}) {
    final image = img.Image(width: size, height: size);
    img.fill(image, color: img.ColorRgb8(r, g, b));
    return Uint8List.fromList(img.encodePng(image));
  }

  String dataUrl(Uint8List bytes) {
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }

  Future<Uint8List> generate({
    required String stampUrl,
    String profileUrl = '',
    String address = 'Test Address 123',
    String salary = 'Rs 50,000',
    String name = 'John Doe',
    String education = "Bachelor's",
    String religion = 'N/A',
    String experienceLevel = '2-5 Years',
  }) {
    return WorkerProfileService.generateWorkerProfile(
      name: name,
      email: 'john@example.com',
      phone: '+123456789',
      fatherHusbandName: 'Doe',
      position: 'Senior Full Stack Software Developer',
      nationalId: '12345',
      attendanceType: 'On-Site',
      workType: 'Full Time',
      experienceLevel: experienceLevel,
      gender: 'Male',
      joiningDate: '01/01/2020',
      salary: salary,
      education: education,
      salaryType: 'Monthly',
      religion: religion,
      dateOfBirth: '01/01/1990',
      relationshipStatus: 'Single',
      address: address,
      profileImageUrl: profileUrl,
      companyName: 'Test Corp',
      companyId: 'TEST123',
      companyStampImageUrl: stampUrl,
    );
  }

  int countImageObjects(Uint8List pdfBytes) {
    final text = latin1.decode(pdfBytes);
    return RegExp(r'/Subtype\s*/Image').allMatches(text).length;
  }

  int countPages(Uint8List pdfBytes) {
    final text = latin1.decode(pdfBytes);
    return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
  }

  testWidgets('worker profile PDF embeds the uploaded stamp image',
      (tester) async {
    await initLocalization(tester);
    final stamp = makePng();
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await generate(stampUrl: dataUrl(stamp));
    });

    expect(pdf.isNotEmpty, isTrue);
    expect(countImageObjects(pdf), greaterThanOrEqualTo(1),
        reason: 'Stamp image should be embedded in the PDF');
  });

  testWidgets('worker profile PDF renders fallback seal when no stamp',
      (tester) async {
    await initLocalization(tester);
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await generate(stampUrl: '');
    });

    expect(pdf.isNotEmpty, isTrue);
    expect(countImageObjects(pdf), 0,
        reason: 'No stamp image should be embedded without a stamp URL');
  });

  testWidgets('worker profile fits one page with realistic photo + long address',
      (tester) async {
    await initLocalization(tester);
    final stamp = makePng();
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await generate(
        stampUrl: dataUrl(stamp),
        profileUrl: dataUrl(makePng(size: 128, r: 30, g: 120, b: 200)),
        address:
            'House No 123, Street 45, Gulberg III, Lahore, Punjab, Pakistan',
      );
    });

    expect(countPages(pdf), 1,
        reason:
            'Stamp must stay on page 1 so it is visible. Actual pages: '
            '${countPages(pdf)}');
  });

  testWidgets('worker profile fits one page with extreme long values',
      (tester) async {
    await initLocalization(tester);
    final stamp = makePng();
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await generate(
        stampUrl: dataUrl(stamp),
        profileUrl: dataUrl(makePng(size: 128, r: 30, g: 120, b: 200)),
        name: 'Muhammad Abdullah Khan Al-Rahman',
        address:
            'House No 123, Street 45, Main Boulevard Gulberg III, Lahore, Punjab, Pakistan 54000',
        salary: 'Rs 1,250,000',
        education:
            'Master of Science in Computer Science (Software Engineering)',
        religion: 'Islam',
        experienceLevel: '10+ Years of Professional Experience',
      );
    });

    expect(countPages(pdf), 1,
        reason:
            'Stamp must stay on page 1 even with long values. Actual pages: '
            '${countPages(pdf)}');
    expect(countImageObjects(pdf), greaterThanOrEqualTo(2),
        reason: 'Both profile photo and stamp should be embedded');
  });
}
