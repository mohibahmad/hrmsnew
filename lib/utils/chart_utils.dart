import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

class ChartData {
  final List<String> labels;
  final List<double> values;
  ChartData(this.labels, this.values);
}

class NiceChartRange {
  final double maxY;
  final double interval;
  NiceChartRange(this.maxY, this.interval);
}

NiceChartRange getNiceRange(double rawMax) {
  if (rawMax <= 0) {
    return NiceChartRange(5, 1);
  }
  if (rawMax <= 5) {
    return NiceChartRange(5, 1);
  } else if (rawMax <= 10) {
    return NiceChartRange(10, 2);
  } else if (rawMax <= 15) {
    return NiceChartRange(15, 3);
  } else if (rawMax <= 20) {
    return NiceChartRange(20, 4);
  } else if (rawMax <= 30) {
    return NiceChartRange(30, 5);
  } else if (rawMax <= 40) {
    return NiceChartRange(40, 8);
  } else if (rawMax <= 50) {
    return NiceChartRange(50, 10);
  } else if (rawMax <= 75) {
    return NiceChartRange(75, 15);
  } else if (rawMax <= 100) {
    return NiceChartRange(100, 20);
  } else if (rawMax <= 150) {
    return NiceChartRange(150, 30);
  } else if (rawMax <= 200) {
    return NiceChartRange(200, 40);
  } else if (rawMax <= 250) {
    return NiceChartRange(250, 50);
  } else if (rawMax <= 300) {
    return NiceChartRange(300, 50);
  } else if (rawMax <= 400) {
    return NiceChartRange(400, 100);
  } else if (rawMax <= 500) {
    return NiceChartRange(500, 100);
  } else if (rawMax <= 600) {
    return NiceChartRange(600, 100);
  } else if (rawMax <= 800) {
    return NiceChartRange(800, 200);
  } else if (rawMax <= 1000) {
    return NiceChartRange(1000, 200);
  } else if (rawMax <= 1500) {
    return NiceChartRange(1500, 300);
  } else if (rawMax <= 2000) {
    return NiceChartRange(2000, 400);
  } else if (rawMax <= 2500) {
    return NiceChartRange(2500, 500);
  } else if (rawMax <= 3000) {
    return NiceChartRange(3000, 500);
  } else if (rawMax <= 4000) {
    return NiceChartRange(4000, 1000);
  } else if (rawMax <= 5000) {
    return NiceChartRange(5000, 1000);
  } else {
    double roughStep = rawMax / 5.0;
    double log10Val = (roughStep.truncate().toString().length - 1).toDouble();
    double power = 1.0;
    for (int i = 0; i < log10Val; i++) {
      power *= 10;
    }
    double normalized = roughStep / power;
    double step;
    if (normalized < 1.5) {
      step = 1.0 * power;
    } else if (normalized < 3.5) {
      step = 2.0 * power;
    } else if (normalized < 7.5) {
      step = 5.0 * power;
    } else {
      step = 10.0 * power;
    }
    double maxY = ((rawMax / step).ceil() * step);
    return NiceChartRange(maxY, step);
  }
}

ChartData getChartData(
  String period,
  List<Map<String, dynamic>> docs,
  bool isGuest,
  String locale,
) {
  final now = DateTime.now();

  if (isGuest || docs.isEmpty) {
    switch (period) {
      case 'Week':
        final labels = <String>[];
        final values = [12.0, 14.0, 8.0, 15.0, 13.0, 11.0, 14.0];
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          labels.add(DateFormat('E', locale).format(date).toUpperCase());
        }
        return ChartData(labels, values);

      case 'Month':
        final labels = [
          'week_label_1'.tr(),
          'week_label_2'.tr(),
          'week_label_3'.tr(),
          'week_label_4'.tr(),
        ];
        final values = [48.0, 55.0, 50.0, 62.0];
        return ChartData(labels, values);

      case '6 Month':
        final labels = <String>[];
        final values = [420.0, 450.0, 480.0, 510.0, 490.0, 530.0];
        for (int i = 5; i >= 0; i--) {
          final date = DateTime(now.year, now.month - i, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
        }
        return ChartData(labels, values);

      case 'Yearly':
      default:
        final labels = <String>[];
        final dummyValues = [
          95.0,
          120.0,
          240.0,
          330.0,
          290.0,
          510.0,
          960.0,
          850.0,
          910.0,
          980.0,
          1020.0,
          1050.0,
        ];
        final values = <double>[];
        for (int i = 0; i < now.month; i++) {
          final date = DateTime(now.year, i + 1, 1);
          labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
          values.add(dummyValues[i]);
        }
        return ChartData(labels, values);
    }
  }

  final parsedRecords = <DateTime>[];
  for (final doc in docs) {
    final createdAt = doc['createdAt'];
    DateTime? dt;
    if (createdAt is Timestamp) {
      dt = createdAt.toDate();
    } else if (createdAt is String) {
      dt = DateTime.tryParse(createdAt);
    }
    if (dt != null) {
      parsedRecords.add(dt);
    }
  }

  switch (period) {
    case 'Week':
      final labels = <String>[];
      final values = List.filled(7, 0.0);
      final startOfWeek = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        labels.add(DateFormat('E', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        final difference = dt.difference(startOfWeek).inDays;
        if (difference >= 0 && difference < 7) {
          values[difference] += 1.0;
        }
      }
      return ChartData(labels, values);

    case 'Month':
      final labels = [
        'week_label_1'.tr(),
        'week_label_2'.tr(),
        'week_label_3'.tr(),
        'week_label_4'.tr(),
      ];
      final values = List.filled(4, 0.0);
      final startOfPeriod = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 27));

      for (final dt in parsedRecords) {
        final difference = dt.difference(startOfPeriod).inDays;
        if (difference >= 0 && difference < 28) {
          final weekIdx = difference ~/ 7;
          if (weekIdx >= 0 && weekIdx < 4) {
            values[weekIdx] += 1.0;
          }
        }
      }
      return ChartData(labels, values);

    case '6 Month':
      final labels = <String>[];
      final values = List.filled(6, 0.0);

      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        for (int i = 0; i < 6; i++) {
          final targetDate = DateTime(now.year, now.month - (5 - i), 1);
          if (dt.year == targetDate.year && dt.month == targetDate.month) {
            values[i] += 1.0;
            break;
          }
        }
      }
      return ChartData(labels, values);

    case 'Yearly':
    default:
      final labels = <String>[];
      final values = List.filled(now.month, 0.0);

      for (int i = 0; i < now.month; i++) {
        final date = DateTime(now.year, i + 1, 1);
        labels.add(DateFormat('MMM', locale).format(date).toUpperCase());
      }

      for (final dt in parsedRecords) {
        if (dt.year == now.year && dt.month <= now.month) {
          values[dt.month - 1] += 1.0;
        }
      }
      return ChartData(labels, values);
  }
}
