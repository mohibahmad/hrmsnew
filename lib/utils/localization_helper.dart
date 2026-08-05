import 'package:easy_localization/easy_localization.dart';
import 'currency_utils.dart';

class LocalizationHelper {
  LocalizationHelper._();

  static String localizeGender(String value) {
    switch (value) {
      case 'Male':
        return 'male'.tr();
      case 'Female':
        return 'female'.tr();
      case 'Other':
      case 'Others':
        return 'other'.tr();
      default:
        return value;
    }
  }

  static String localizeType1(String value) {
    switch (value) {
      case 'Full-Time':
      case 'full_time':
      case 'Full Time':
      case 'employee':
        return 'full_time'.tr();
      case 'Part-Time':
      case 'part_time':
      case 'Part Time':
        return 'part_time'.tr();
      case 'Contract':
      case 'contract':
        return 'contract'.tr();
      case 'Freelance':
      case 'freelance':
        return 'freelance'.tr();
      default:
        return value;
    }
  }

  static String localizeType2(String value) {
    switch (value) {
      case 'On-Site':
      case 'on_site':
        return 'on_site'.tr();
      case 'Remote':
      case 'remote':
        return 'remote'.tr();
      case 'Hybrid':
      case 'hybrid':
        return 'hybrid'.tr();
      default:
        return value;
    }
  }

  static String localizeExperience(String value) {
    switch (value) {
      case 'Fresher':
      case 'fresher':
        return 'fresher'.tr();
      case 'Junior':
      case 'junior':
        return 'junior'.tr();
      case 'Mid-Level':
      case 'mid_level':
      case 'Mid Level':
        return 'mid_level'.tr();
      case 'Senior':
      case 'senior':
        return 'senior'.tr();
      default:
        return value;
    }
  }

  static String localizePosition(String value) {
    switch (value.toLowerCase()) {
      case 'designer':
        return 'designer'.tr();
      case 'developer':
        return 'developer'.tr();
      case 'engineering':
        return 'engineering'.tr();
      case 'sales':
        return 'sales'.tr();
      case 'management':
        return 'management'.tr();
      case 'manager':
        return 'manager'.tr();
      case 'accountant':
        return 'accountant'.tr();
      case 'assistant':
        return 'assistant'.tr();
      case 'director':
        return 'director'.tr();
      case 'lead':
        return 'lead'.tr();
      case 'engineer':
        return 'engineer'.tr();
      case 'analyst':
        return 'analyst'.tr();
      case 'coordinator':
        return 'coordinator'.tr();
      case 'consultant':
        return 'consultant'.tr();
      case 'officer':
        return 'officer'.tr();
      case 'specialist':
        return 'specialist'.tr();
      case 'administrator':
        return 'administrator'.tr();
      case 'researcher':
        return 'researcher'.tr();
      case 'writer':
        return 'writer'.tr();
      case 'tester':
        return 'tester'.tr();
      case 'strategist':
        return 'strategist'.tr();
      case 'architect':
        return 'architect'.tr();
      case 'marketing':
        return 'marketing'.tr();
      case 'operations':
        return 'operations'.tr();
      case 'it support':
        return 'it_support'.tr();
      case 'quality assurance':
        return 'quality_assurance'.tr();
      case 'product':
        return 'product'.tr();
      case 'research':
        return 'research'.tr();
      case 'legal':
        return 'legal'.tr();
      default:
        return _localizeCompoundPosition(value);
    }
  }

  static String _localizeCompoundPosition(String value) {
    final words = value.split(' ');
    if (words.length <= 1) {
      if (value.isEmpty) return value;
      return value[0].toUpperCase() + value.substring(1);
    }
    final parts = words.map((w) {
      final lower = w.toLowerCase();
      switch (lower) {
        case 'manager':
          return 'manager'.tr();
        case 'developer':
          return 'developer'.tr();
        case 'designer':
          return 'designer'.tr();
        case 'engineer':
          return 'engineer'.tr();
        case 'analyst':
          return 'analyst'.tr();
        case 'director':
          return 'director'.tr();
        case 'lead':
          return 'lead'.tr();
        case 'coordinator':
          return 'coordinator'.tr();
        case 'specialist':
          return 'specialist'.tr();
        case 'assistant':
          return 'assistant'.tr();
        case 'tester':
          return 'tester'.tr();
        case 'writer':
          return 'writer'.tr();
        case 'architect':
          return 'architect'.tr();
        case 'marketing':
          return 'marketing'.tr();
        case 'operations':
          return 'operations'.tr();
        case 'product':
          return 'product'.tr();
        case 'research':
          return 'research'.tr();
        case 'legal':
          return 'legal'.tr();
        default:
          // Unknown words (e.g. custom positions like "real state") are
          // title-cased so "real state" shows as "Real State" instead of
          // staying lowercase.
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1);
      }
    }).toList();
    return parts.join(' ');
  }

  static String localizeEducation(String value) {
    switch (value) {
      case 'Matric':
      case 'matric':
        return 'matric'.tr();
      case 'Intermediate':
      case 'intermediate':
        return 'intermediate'.tr();
      case 'Bachelor':
      case 'bachelor':
        return 'bachelor'.tr();
      case 'Master':
      case 'master':
        return 'master'.tr();
      case 'Other':
      case 'other':
        return 'other'.tr();
      default:
        return value;
    }
  }

  static String localizeSalaryType(String value) {
    switch (value) {
      case 'Monthly':
      case 'monthly':
      case 'fixed':
        return 'monthly'.tr();
      case 'Hourly':
      case 'hourly':
        return 'hourly'.tr();
      case 'Contract':
      case 'contract':
        return 'contract'.tr();
      default:
        return value;
    }
  }

  static String localizeCurrency(String value) {
    switch (CurrencyUtils.normalize(value)) {
      case 'USD':
        return 'usd_desc'.tr();
      case 'EUR':
        return 'eur_desc'.tr();
      case 'GBP':
        return 'gbp_desc'.tr();
      case 'JPY':
        return 'jpy_desc'.tr();
      case 'INR':
        return 'inr_desc'.tr();
      case 'PKR':
        return 'pkr_desc'.tr();
      case 'RUB':
        return 'rub_desc'.tr();
      case 'BRL':
        return 'brl_desc'.tr();
      case 'SAR':
        return 'sar_desc'.tr();
      case 'AED':
        return 'aed_desc'.tr();
      case 'CAD':
        return 'cad_desc'.tr();
      case 'AUD':
        return 'aud_desc'.tr();
      case 'QAR':
        return 'qar_desc'.tr();
      case 'KWD':
        return 'kwd_desc'.tr();
      case 'OMR':
        return 'omr_desc'.tr();
      default:
        return value;
    }
  }

  static String localizeLeavePolicy(String value) {
    switch (value) {
      case 'Standard':
      case 'standard':
        return 'standard'.tr();
      case 'Custom':
      case 'custom':
        return 'custom'.tr();
      case 'Sick/Casual Only':
      case 'sick_casual_only':
        return 'sick_casual_only'.tr();
      default:
        return value;
    }
  }

  static String localizeWorkType(String value) {
    switch (value) {
      case 'Full Time':
      case 'full_time':
      case 'Full-Time':
      case 'employee':
        return 'full_time'.tr();
      case 'Part Time':
      case 'part_time':
      case 'Part-Time':
        return 'part_time'.tr();
      case 'Contract':
      case 'contract':
        return 'contract'.tr();
      default:
        return value;
    }
  }

  static String localizeAttendanceType(String value) {
    switch (value) {
      case 'On-Site':
      case 'on_site':
        return 'on_site'.tr();
      case 'Remote':
      case 'remote':
        return 'remote'.tr();
      case 'Hybrid':
      case 'hybrid':
        return 'hybrid'.tr();
      default:
        return value;
    }
  }

  static String localizeLeaveAction(String value) {
    switch (value) {
      case 'Sick':
      case 'sick':
        return 'sick'.tr();
      case 'Casual':
      case 'casual':
        return 'casual'.tr();
      case 'Annual':
      case 'annual':
        return 'annual'.tr();
      case 'Unpaid':
      case 'unpaid':
        return 'unpaid'.tr();
      case 'Maternity':
      case 'maternity':
        return 'maternity'.tr();
      case 'Paternity':
      case 'paternity':
        return 'paternity'.tr();
      default:
        return value;
    }
  }
}
