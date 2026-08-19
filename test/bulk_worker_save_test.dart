import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/models/worker.dart';
import 'package:hrms/utils/utils.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  test('Bulk Worker Save Data Normalization', () {
    final workerMap = <String, dynamic>{
      'name': 'Olivia Wilson',
      'phone': '+61 412 345 678',
      'email': 'olivia.wilson@gmail.com',
      'position': 'Cybersecurity',
      'salaryAmount': '145000',
      'dob': '01/01/1995',
      'gender': 'Female',
      'type1': 'Full-Time',
      'type2': 'On-Site',
    };

    final clean = Map<String, dynamic>.from(workerMap);
    final workerObj = Worker.fromMap(clean);
    final toMapResult = workerObj.toMap();
    expect(toMapResult['name'], equals('Olivia Wilson'));
    expect(toMapResult['salaryAmount'], equals(145000.0));

    final canonical = TimeOffService.canonicalWorkerLeaveFields(toMapResult);
    expect(canonical, isNotNull);
  });
}
