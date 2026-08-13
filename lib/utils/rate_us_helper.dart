import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/preferences_service.dart';

Future<void> showRateUsDialogNow() async {
  _requestReview();
}

Future<bool> tryShowRateUsDialog() async {
  if (await PreferencesService.getRateUsNeverShow()) return false;
  _requestReview();
  return true;
}

Future<bool> tryShowFirstMilestoneRateUs(String milestone) async {
  if (await PreferencesService.getRateUsNeverShow()) return false;
  bool alreadyTriggered;
  Future<void> Function() markTriggered;
  switch (milestone) {
    case 'expense':
      alreadyTriggered = await PreferencesService.wasFirstExpenseTriggered();
      markTriggered = PreferencesService.markFirstExpenseTriggered;
      break;
    case 'worker':
      alreadyTriggered = await PreferencesService.wasFirstWorkerTriggered();
      markTriggered = PreferencesService.markFirstWorkerTriggered;
      break;
    case 'holiday':
      alreadyTriggered = await PreferencesService.wasFirstHolidayTriggered();
      markTriggered = PreferencesService.markFirstHolidayTriggered;
      break;
    case 'bulk_worker':
      alreadyTriggered = await PreferencesService.wasFirstBulkWorkerTriggered();
      markTriggered = PreferencesService.markFirstBulkWorkerTriggered;
      break;
    case 'asset':
      alreadyTriggered = await PreferencesService.wasFirstAssetTriggered();
      markTriggered = PreferencesService.markFirstAssetTriggered;
      break;
    default:
      return false;
  }

  if (alreadyTriggered) return false;

  await markTriggered();
  _requestReview();
  return true;
}

Future<void> _requestReview() async {
  await PreferencesService.setRateUsNeverShow(true);
  try {
    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
    } else {
      await launchUrl(
        Uri.parse(
          'https://apps.apple.com/app/hrms-workforce-manager/id6743024022',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {}
}
