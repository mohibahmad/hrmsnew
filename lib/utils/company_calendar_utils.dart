class CompanyCalendarRecords {
  final List<Map<String, dynamic>> holidays;
  final Set<int> workingDays;

  const CompanyCalendarRecords({
    required this.holidays,
    required this.workingDays,
  });
}

Set<int> validWorkingDays(
  dynamic rawDays, {
  bool acceptNumericStrings = false,
}) {
  if (rawDays is! Iterable) return const <int>{};

  final days = <int>{};
  for (final value in rawDays) {
    final day = value is num
        ? value.toInt()
        : acceptNumericStrings
        ? int.tryParse(value.toString().trim())
        : null;
    if (day != null && day >= DateTime.monday && day <= DateTime.sunday) {
      days.add(day);
    }
  }
  return days;
}

CompanyCalendarRecords splitCompanyCalendarRecords(
  Iterable<Map<String, dynamic>> records, {
  required Set<int> fallbackWorkingDays,
  bool acceptNumericStrings = false,
}) {
  final holidays = <Map<String, dynamic>>[];
  var workingDays = fallbackWorkingDays;

  for (final record in records) {
    if (record['type'] != 'company_work_days') {
      holidays.add(record);
      continue;
    }

    final savedDays = validWorkingDays(
      record['workingDays'],
      acceptNumericStrings: acceptNumericStrings,
    );
    if (savedDays.isNotEmpty) workingDays = savedDays;
  }

  return CompanyCalendarRecords(holidays: holidays, workingDays: workingDays);
}
