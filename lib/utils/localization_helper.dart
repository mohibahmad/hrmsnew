import 'package:easy_localization/easy_localization.dart';

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
        return 'full_time'.tr();
      case 'Part-Time':
        return 'part_time'.tr();
      case 'Contract':
        return 'contract'.tr();
      case 'Freelance':
        return 'freelance'.tr();
      default:
        return value;
    }
  }

  static String localizeType2(String value) {
    switch (value) {
      case 'On-Site':
        return 'on_site'.tr();
      case 'Remote':
        return 'remote'.tr();
      case 'Hybrid':
        return 'hybrid'.tr();
      default:
        return value;
    }
  }

  static String localizeExperience(String value) {
    switch (value) {
      case 'Fresher':
        return 'fresher'.tr();
      case 'Junior':
        return 'junior'.tr();
      case 'Mid-Level':
        return 'mid_level'.tr();
      case 'Senior':
        return 'senior'.tr();
      default:
        return value;
    }
  }

  static String localizeEducation(String value) {
    switch (value) {
      case 'Matric':
        return 'matric'.tr();
      case 'Intermediate':
        return 'intermediate'.tr();
      case 'Bachelor':
        return 'bachelor'.tr();
      case 'Master':
        return 'master'.tr();
      case 'Other':
        return 'other'.tr();
      default:
        return value;
    }
  }

  static String localizeSalaryType(String value) {
    switch (value) {
      case 'Monthly':
        return 'monthly'.tr();
      case 'Hourly':
        return 'hourly'.tr();
      case 'Contract':
        return 'contract'.tr();
      default:
        return value;
    }
  }

  static String localizeCurrency(String value) {
    switch (value) {
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
      case 'RUB':
        return 'rub_desc'.tr();
      case 'BRL':
        return 'brl_desc'.tr();
      case 'SAR':
        return 'sar_desc'.tr();
      default:
        return value;
    }
  }

  static String localizeLeavePolicy(String value) {
    switch (value) {
      case 'Standard':
        return 'standard'.tr();
      case 'Custom':
        return 'custom'.tr();
      case 'Sick/Casual Only':
        return 'sick_casual_only'.tr();
      default:
        return value;
    }
  }

  static String localizeWorkType(String value) {
    switch (value) {
      case 'Full Time':
        return 'full_time'.tr();
      case 'Part Time':
        return 'part_time'.tr();
      case 'Contract':
        return 'contract'.tr();
      default:
        return value;
    }
  }

  static String localizeAttendanceType(String value) {
    switch (value) {
      case 'On-Site':
        return 'on_site'.tr();
      case 'Remote':
        return 'remote'.tr();
      case 'Hybrid':
        return 'hybrid'.tr();
      default:
        return value;
    }
  }

  static String localizeLeaveAction(String value) {
    switch (value) {
      case 'Sick':
        return 'sick'.tr();
      case 'Casual':
        return 'casual'.tr();
      case 'Annual':
        return 'annual'.tr();
      case 'Unpaid':
        return 'unpaid'.tr();
      case 'Maternity':
        return 'maternity'.tr();
      case 'Paternity':
        return 'paternity'.tr();
      default:
        return value;
    }
  }
}
