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
    final isGuest = PreferencesService.cachedIsGuest;
    Map<String, dynamic>? profile;
    if (!isGuest && firestore != null) {
      try {
        profile = await firestore.getUserProfile();
      } catch (_) {
        profile = null;
      }
    }

    Map<String, String>? guestProfile;
    if (isGuest) {
      try {
        guestProfile = await PreferencesService.getGuestProfileData();
      } catch (_) {
        guestProfile = null;
      }
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
      profilePicUrl = (profile['profilePic'] ?? '').toString().trim();
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

    if (isGuest && profilePicUrl.isEmpty) {
      try {
        profilePicUrl = (await PreferencesService.getProfilePicUrl() ?? '')
            .trim();
      } catch (_) {}
    }

    if (isGuest) {
      final notifierPic = AuthService.profilePicNotifier.value ?? '';
      if (notifierPic.isNotEmpty) {
        profilePicUrl = notifierPic;
      }
    }

    String companyStampUrl = '';

    if (profile != null) {
      companyStampUrl = (profile['companyStampUrl'] ?? '').toString().trim();
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

    if (isGuest && companyStampUrl.isEmpty) {
      try {
        companyStampUrl = (await PreferencesService.getCompanyStampUrl() ?? '')
            .trim();
      } catch (_) {}
    }

    if (isGuest && companyStampUrl.isEmpty) {
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

    return {
      'companyName': companyName,
      'companyId': companyId,
      'profilePicUrl': profilePicUrl,
      'companyStampUrl': companyStampUrl,
      'address': address,
      'email': email,
      'phone': phone,
    };
  }
}
