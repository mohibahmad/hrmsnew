import 'dart:convert';
import 'dart:io' as io;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../utils/file_opener.dart';
import '../utils/snackbar_utils.dart';

List<List<String>> parseCsvInBackground(Uint8List bytes) {
  var csvString = utf8.decode(bytes, allowMalformed: true);
  if (csvString.isNotEmpty && csvString.codeUnitAt(0) == 0xFEFF) {
    csvString = csvString.substring(1);
  }
  csvString = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rows = Csv(dynamicTyping: false).decode(csvString);
  return rows.map((row) => row.map((e) => e.toString()).toList()).toList();
}

String computeFileHash(Uint8List bytes) {
  int hash = 0x811C9DC5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return '${bytes.length}_${hash.toRadixString(16)}';
}

Future<void> downloadTemplate(BuildContext context) async {
  const headerRow =
      'Full Name,Contact Number,Email Address,Father Name,National ID,'
      'Religion,Date of Birth,Gender,Address,Relationship Status,'
      'Job Position,Employee Type,Work Model,Experience Level,Education,'
      'Monthly Salary Amount,Annual Leaves,Sick Leaves,Casual Leaves,'
      'Medical Leaves,Joining Date,'
      'Profile Image,Front ID Image,Back ID Image,CV';

  const dataRows =
      'John Doe,1234567890,john@gmail.com,Robert Doe,37405-1234567-1,'
      'Christianity,15/05/1990,Male,123 Street California,Single,'
      'Software Engineer,Full-Time,On-Site,Mid-Level,Bachelor\'s,'
      '5000,15,10,5,5,15/01/2025,'
      'https://i.pravatar.cc/150?u=john,https://picsum.photos/seed/john_front/400/300,'
      'https://picsum.photos/seed/john_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
      'Jane Smith,0987654321,jane@gmail.com,David Smith,37405-7654321-2,'
      'Islam,20/10/1995,Female,456 Avenue New York,Married,'
      'UI Designer,Part-Time,Remote,Senior,Bachelor\'s,'
      '6000,15,10,5,5,15/01/2025,'
      'https://i.pravatar.cc/150?u=jane,https://picsum.photos/seed/jane_front/400/300,'
      'https://picsum.photos/seed/jane_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
      'Michael Johnson,1122334455,michael@gmail.com,Alan Johnson,37405-1122334-3,'
      'None,28/02/1988,Male,789 Road Texas,Single,'
      'Project Manager,Contract,Hybrid,Senior,Master\'s,'
      '7500,15,10,5,5,15/01/2025,'
      'https://i.pravatar.cc/150?u=michael,https://picsum.photos/seed/michael_front/400/300,'
      'https://picsum.photos/seed/michael_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
      'Emily Brown,5551234567,emily@gmail.com,Thomas Brown,37405-9988776-5,'
      'Christianity,08/07/1992,Female,321 Oak Avenue Chicago,Married,'
      'Marketing Manager,Full-Time,On-Site,Senior,Master\'s,'
      '8500,20,10,5,5,20/01/2025,'
      'https://i.pravatar.cc/150?u=emily,https://picsum.photos/seed/emily_front/400/300,'
      'https://picsum.photos/seed/emily_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
      'Carlos Garcia,5559876543,carlos@gmail.com,Luis Garcia,37405-4433221-4,'
      'Catholic,22/03/1985,Male,654 Pine Road Miami,Single,'
      'DevOps Engineer,Full-Time,On-Site,Senior,Bachelor\'s,'
      '9500,18,10,5,5,01/02/2025,'
      'https://i.pravatar.cc/150?u=carlos,https://picsum.photos/seed/carlos_front/400/300,'
      'https://picsum.photos/seed/carlos_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
      'Aisha Khan,5552468135,aisha@gmail.com,Imran Khan,37405-5566778-7,'
      'Islam,12/11/1993,Female,789 Maple Drive Houston,Single,'
      'Data Analyst,Full-Time,Hybrid,Mid-Level,Bachelor\'s,'
      '7000,15,10,5,5,05/02/2025,'
      'https://i.pravatar.cc/150?u=aisha,https://picsum.photos/seed/aisha_front/400/300,'
      'https://picsum.photos/seed/aisha_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf\n'
      'Robert Wilson,5553691479,robert@gmail.com,James Wilson,37405-1122334-8,'
      'None,05/09/1980,Male,147 Elm Street Seattle,Married,'
      'HR Director,Full-Time,On-Site,Senior,Master\'s,'
      '110000,20,10,5,5,10/01/2025,'
      'https://i.pravatar.cc/150?u=robert,https://picsum.photos/seed/robert_front/400/300,'
      'https://picsum.photos/seed/robert_back/400/300,https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';

  const templateStr = '$headerRow\n$dataRows';

  try {
    final String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'save_worker_template'.tr(),
      fileName: 'worker_template.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(templateStr)),
    );

    if (outputFile == null) return;

    await io.File(outputFile).writeAsString(templateStr);

    FlashySnackBar.show(context, message: 'template_saved_successfully'.tr());
    await FileOpener.open(outputFile);
  } catch (_) {
    FlashySnackBar.show(
      context,
      message: 'could_not_download_template'.tr(),
      isError: true,
    );
  }
}

Future<Uint8List?> pickCsvFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
    withData: true,
  );

  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  const int maxBytes = 5 * 1024 * 1024;

  if (file.bytes != null && file.bytes!.length > maxBytes) {
    return null;
  }

  Uint8List? bytes = file.bytes;

  if (bytes == null && file.path != null) {
    final diskFile = io.File(file.path!);
    if (await diskFile.length() > maxBytes) {
      return null;
    }
    bytes = await diskFile.readAsBytes();
  }

  return bytes;
}
