import 'package:easy_localization/easy_localization.dart';
import 'currency_utils.dart';

class LocalizationHelper {
  LocalizationHelper._();

  /// Canonical Firebase values used as filter keys. Only the visible label is
  /// localized so filtering keeps working after the app language changes.
  static const List<String> defaultJobPositions = [
    'Designer',
    'Developer',
    'Software Engineer',
    'Sales',
    'HR',
    'Finance',
    'Marketing',
    'Operations',
    'IT Support',
    'Product',
    'Research',
  ];

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

  /// Full-phrase job roles (mostly the guest demo dataset). Only these exact
  /// canonical phrases are translated; HR-created roles always stay as-is.
  static const Map<String, String> _compoundRoleKeys = {
    'backend developer': 'backend_developer',
    'backend engineer': 'backend_engineer',
    'business analyst': 'business_analyst',
    'cloud architect': 'cloud_architect',
    'content strategist': 'content_strategist',
    'content writer': 'content_writer',
    'cyber security analyst': 'cyber_security_analyst',
    'data analyst': 'data_analyst',
    'data engineer': 'data_engineer',
    'devops engineer': 'devops_engineer',
    'devops lead': 'devops_lead',
    'event coordinator': 'event_coordinator',
    'finance analyst': 'finance_analyst',
    'frontend developer': 'frontend_developer',
    'graphic designer': 'graphic_designer',
    'hr manager': 'hr_manager',
    'it support specialist': 'it_support_specialist',
    'junior developer': 'junior_developer',
    'junior qa tester': 'junior_qa_tester',
    'marketing lead': 'marketing_lead',
    'mobile developer': 'mobile_developer',
    'office manager': 'office_manager',
    'operations manager': 'operations_manager',
    'product manager': 'product_manager',
    'qa engineer': 'qa_engineer',
    'sales executive': 'sales_executive',
    'senior web developer': 'senior_web_developer',
    'social media manager': 'social_media_manager',
    'solutions architect': 'solutions_architect',
    'system administrator': 'system_administrator',
    'technical writer': 'technical_writer',
    'ui designer': 'ui_designer',
    'ux researcher': 'ux_researcher',
  };

  static String localizePosition(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    switch (normalized) {
      case 'designer':
        return 'designer'.tr();
      case 'developer':
        return 'developer'.tr();
      case 'engineering':
        return 'engineering'.tr();
      case 'sales':
        return 'sales'.tr();
      case 'hr':
      case 'human resources':
        return 'hr'.tr();
      case 'finance':
        return 'finance'.tr();
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
      case 'software engineer':
        return 'software_engineer'.tr();
      case 'quality assurance':
        return 'quality_assurance'.tr();
      case 'product':
        return 'product'.tr();
      case 'research':
        return 'research'.tr();
      case 'legal':
        return 'legal'.tr();
      default:
        final compoundKey = _compoundRoleKeys[normalized];
        if (compoundKey != null) return compoundKey.tr();
        return _localizeCompoundPosition(value.trim());
    }
  }

  static String _localizeCompoundPosition(String value) {
    if (value.isEmpty) return value;
    final words = value.split(' ');
    final parts = words.map((w) {
      if (w.isEmpty) return w;
      final lower = w.toLowerCase();
      if (_jobRoleAcronyms.contains(lower)) return lower.toUpperCase();
      return w[0].toUpperCase() + w.substring(1);
    }).toList();
    return parts.join(' ');
  }

  static const Set<String> _jobRoleAcronyms = {
    'hr',
    'it',
    'qa',
    'ui',
    'ux',
    'ceo',
    'cto',
    'cfo',
    'coo',
  };

  static String localizeEducation(String value) {
    switch (value) {
      case 'Matric':
      case 'matric':
        return 'matric'.tr();
      case 'Intermediate':
      case 'intermediate':
        return 'intermediate'.tr();
      case 'Bachelor':
      case 'Bachelors':
      case 'bachelor':
      case 'bachelors':
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

  /// Localizes expense category labels (e.g. 'Salary', 'Rent', 'Food &
  /// Beverage'). Unknown/typed categories fall back to the raw value so
  /// display follows the app language without breaking stored data.
  static String localizeExpenseCategory(String value) {
    switch (value.trim().toLowerCase()) {
      case 'salary':
        return 'expense_cat_salary'.tr();
      case 'stationery':
        return 'expense_cat_stationery'.tr();
      case 'food & beverage':
      case 'food_and_beverage':
        return 'expense_cat_food_beverage'.tr();
      case 'software & it':
      case 'software_and_it':
        return 'expense_cat_software_it'.tr();
      case 'rent':
        return 'expense_cat_rent'.tr();
      case 'entertainment':
        return 'expense_cat_entertainment'.tr();
      case 'training & development':
      case 'training_and_development':
        return 'expense_cat_training_development'.tr();
      case 'utilities':
        return 'expense_cat_utilities'.tr();
      case 'furniture':
        return 'expense_cat_furniture'.tr();
      case 'professional services':
      case 'professional_services':
        return 'expense_cat_professional_services'.tr();
      default:
        return value;
    }
  }

  /// Localizes leave type labels (e.g. 'Sick Leave', 'Casual', 'Annual
  /// Leave') used in the dashboard leave chart. Unknown values fall back to
  /// the raw type so the color/label mapping keeps working in any language.
  static String localizeLeaveType(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_');
    switch (normalized) {
      case 'casual_leave':
      case 'casual':
        return 'leave_casual'.tr();
      case 'sick_leave':
      case 'sick':
        return 'leave_sick'.tr();
      case 'medical_leave':
      case 'medical':
        return 'leave_medical'.tr();
      case 'annual_leave':
      case 'annual':
        return 'leave_annual'.tr();
      case 'maternity_leave':
      case 'maternity':
        return 'leave_maternity'.tr();
      case 'paternity_leave':
      case 'paternity':
        return 'leave_paternity'.tr();
      case 'unpaid_leave':
      case 'unpaid':
        return 'leave_unpaid'.tr();
      case 'emergency_leave':
      case 'emergency':
        return 'leave_emergency'.tr();
      case 'study_leave':
      case 'study':
        return 'leave_study'.tr();
      case 'hajj_leave':
      case 'hajj':
        return 'leave_hajj'.tr();
      default:
        return value;
    }
  }

  /// Localizes the raw biometric label reported by the device (e.g.
  /// "Fingerprint", "Face ID") so auth-prompt reason strings are fully
  /// localized instead of mixing English labels into translated sentences.
  static String localizeBiometricName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'face id':
        return 'biometric_face_id'.tr();
      case 'fingerprint':
      case 'touch id':
        return 'biometric_fingerprint'.tr();
      case 'iris':
        return 'biometric_iris'.tr();
      default:
        return 'biometric_generic'.tr();
    }
  }

  /// Localizes the seeded holiday names shown on the Home upcoming-holidays
  /// cards. Unknown/custom holiday names fall back to the raw value.
  static String localizeHolidayName(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    switch (normalized) {
      case 'new_years_day':
        return 'holiday_name_new_years_day'.tr();
      case 'martin_luther_king_jr_day':
        return 'holiday_name_mlk_day'.tr();
      case 'valentines_day':
        return 'holiday_name_valentines_day'.tr();
      case 'presidents_day':
        return 'holiday_name_presidents_day'.tr();
      case 'spring_equinox':
        return 'holiday_name_spring_equinox'.tr();
      case 'easter_sunday':
        return 'holiday_name_easter_sunday'.tr();
      case 'earth_day':
        return 'holiday_name_earth_day'.tr();
      case 'memorial_day':
        return 'holiday_name_memorial_day'.tr();
      case 'juneteenth':
        return 'holiday_name_juneteenth'.tr();
      case 'independence_day':
        return 'holiday_name_independence_day'.tr();
      case 'national_intern_day':
        return 'holiday_name_national_intern_day'.tr();
      case 'international_cat_day':
        return 'holiday_name_international_cat_day'.tr();
      case 'summer_picnic':
        return 'holiday_name_summer_picnic'.tr();
      case 'world_photography_day':
        return 'holiday_name_world_photography_day'.tr();
      case 'womens_equality_day':
        return 'holiday_name_womens_equality_day'.tr();
      case 'labor_day':
        return 'holiday_name_labor_day'.tr();
      case 'patriot_day':
        return 'holiday_name_patriot_day'.tr();
      case 'international_day_of_peace':
        return 'holiday_name_international_day_of_peace'.tr();
      case 'world_teachers_day':
        return 'holiday_name_world_teachers_day'.tr();
      case 'columbus_day':
        return 'holiday_name_columbus_day'.tr();
      case 'united_nations_day':
        return 'holiday_name_united_nations_day'.tr();
      case 'halloween':
        return 'holiday_name_halloween'.tr();
      case 'veterans_day':
        return 'holiday_name_veterans_day'.tr();
      case 'world_kindness_day':
        return 'holiday_name_world_kindness_day'.tr();
      case 'thanksgiving_day':
        return 'holiday_name_thanksgiving_day'.tr();
      case 'black_friday':
        return 'holiday_name_black_friday'.tr();
      case 'human_rights_day':
        return 'holiday_name_human_rights_day'.tr();
      case 'winter_solstice':
        return 'holiday_name_winter_solstice'.tr();
      case 'christmas_eve':
        return 'holiday_name_christmas_eve'.tr();
      case 'christmas_day':
        return 'holiday_name_christmas_day'.tr();
      case 'boxing_day':
        return 'holiday_name_boxing_day'.tr();
      case 'new_years_eve':
        return 'holiday_name_new_years_eve'.tr();
      default:
        return value;
    }
  }
}
