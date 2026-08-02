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
