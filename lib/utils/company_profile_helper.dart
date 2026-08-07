import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';

class CompanyProfileHelper {
  
  static String companyNameOrFallback(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? 'HRMS Company' : trimmed;
  }

  static Future<Map<String, dynamic>> getCompanyProfileWithFirestore(
    FirestoreService? firestore,
  ) async {
    Map<String, dynamic>? profile;
    if (firestore != null) {
      try {
        profile = await firestore.getUserProfile();
      } catch (_) {
        profile = null;
      }
    }

    Map<String, String>? guestProfile;
    try {
      guestProfile = await PreferencesService.getGuestProfileData();
    } catch (_) {
      guestProfile = null;
    }

    
    final companyName =
        (profile?['businessName'] ??
                profile?['companyName'] ??
                guestProfile?['businessName'] ??
                guestProfile?['companyName'] ??
                '')
            .toString()
            .trim();

    
    final companyId =
        (profile?['companyId'] ??
                profile?['businessId'] ??
                guestProfile?['companyId'] ??
                guestProfile?['businessId'] ??
                '')
            .toString()
            .trim();

    
    String profilePicUrl = '';

    
    if (profile != null) {
      profilePicUrl =
          (profile['profilePic'] ??
                  profile['profilePicUrl'] ??
                  profile['photoUrl'] ??
                  profile['companyLogoUrl'] ??
                  '')
              .toString()
              .trim();
    }

    
    if (profilePicUrl.isEmpty && guestProfile != null) {
      profilePicUrl =
          (guestProfile['profilePic'] ??
                  guestProfile['profilePicUrl'] ??
                  guestProfile['photoUrl'] ??
                  guestProfile['companyLogoUrl'] ??
                  '')
              .toString()
              .trim();
    }

    
    if (profilePicUrl.isEmpty) {
      try {
        profilePicUrl = (await PreferencesService.getProfilePicUrl() ?? '')
            .trim();
      } catch (_) {}
    }

    
    final notifierPic = AuthService.profilePicNotifier.value ?? '';
    if (notifierPic.isNotEmpty) {
      profilePicUrl = notifierPic;
    }

    
    String companyStampUrl = '';

    
    if (profile != null) {
      companyStampUrl =
          (profile['companyStampUrl'] ??
                  profile['stampUrl'] ??
                  profile['companyStamp'] ??
                  profile['companySignature'] ??
                  profile['signatureUrl'] ??
                  profile['signature'] ??
                  '')
              .toString()
              .trim();
    }

    
    if (companyStampUrl.isEmpty && guestProfile != null) {
      companyStampUrl =
          (guestProfile['companyStampUrl'] ??
                  guestProfile['stampUrl'] ??
                  guestProfile['companyStamp'] ??
                  guestProfile['companySignature'] ??
                  guestProfile['signatureUrl'] ??
                  guestProfile['signature'] ??
                  '')
              .toString()
              .trim();
    }

    
    if (companyStampUrl.isEmpty) {
      try {
        companyStampUrl = (await PreferencesService.getCompanyStampUrl() ?? '')
            .trim();
      } catch (_) {}
    }

    
    if (companyStampUrl.isEmpty) {
      final notifierStamp = AuthService.companyStampNotifier.value ?? '';
      if (notifierStamp.isNotEmpty) {
        companyStampUrl = notifierStamp;
      }
    }

    
    final address = (profile?['address'] ?? guestProfile?['address'] ?? '')
        .toString()
        .trim();

    
    final email = (profile?['email'] ?? guestProfile?['email'] ?? '')
        .toString()
        .trim();

    
    final phone =
        (profile?['contact1'] ??
                profile?['phone'] ??
                guestProfile?['contact1'] ??
                guestProfile?['phone'] ??
                '')
            .toString()
            .trim();

    
    final rawSalaryDay = profile?['salaryPaymentDay'] ??
        profile?['salaryDay'] ??
        guestProfile?['salaryPaymentDay'] ??
        guestProfile?['salaryDay'];
    int? salaryDay;
    if (rawSalaryDay is num) {
      salaryDay = rawSalaryDay.toInt();
    } else if (rawSalaryDay != null) {
      salaryDay = int.tryParse(rawSalaryDay.toString());
    }
    if (salaryDay == null) {
      try {
        salaryDay = await PreferencesService.getCompanySalaryDay();
      } catch (_) {}
    }

    return {
      'companyName': companyName,
      'companyId': companyId,
      'profilePicUrl': profilePicUrl,
      'companyStampUrl': companyStampUrl,
      'address': address,
      'email': email,
      'phone': phone,
      'salaryDay': salaryDay,
    };
  }
}
