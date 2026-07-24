import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/error_reporter.dart';
import '../utils/snackbar_utils.dart';

Future<bool> handleDeletedAccountIfNeeded(
  BuildContext context,
  AuthService authService,
) async {
  final user = authService.currentUser;
  if (user == null) return false;

  if (user.isAnonymous || user.uid.startsWith('guest_')) return false;

  final email = user.email;
  if (email == null || email.isEmpty) return false;

  try {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final isDeleted = await firestoreService.isCurrentUserDeleted();
    if (isDeleted) {
      await authService.signOut();
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'account_deleted_contact'.tr(),
          isError: true,
        );
      }
      return true;
    }
  } catch (e, st) {
    ErrorReporter.report(e, st, context: 'handleDeletedAccount');
  }

  return false;
}
