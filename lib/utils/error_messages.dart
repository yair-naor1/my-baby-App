import 'package:firebase_auth/firebase_auth.dart';

import '../services/photo_storage_service.dart';

/// Firebase Auth error codes whose default `.message` is genuinely written
/// for an end user (e.g. "The password is invalid"). Any other code —
/// `operation-not-allowed`, `internal-error`, `configuration-not-found`, and
/// the like — is a developer/ops message (sometimes literally telling the
/// reader to go edit the Firebase console) and must never reach the UI.
const _userFacingAuthCodes = {
  'wrong-password',
  'invalid-credential',
  'user-not-found',
  'user-disabled',
  'invalid-email',
  'email-already-in-use',
  'weak-password',
  'too-many-requests',
  'network-request-failed',
  'requires-recent-login',
  'account-exists-with-different-credential',
  'credential-already-in-use',
};

/// Turns any thrown error into text that is safe to show a parent.
///
/// Never surfaces raw provider/internal detail (Drive, Firestore error
/// codes, stack-trace-shaped text, or Firebase Auth setup instructions) —
/// see PRODUCT_SPEC.md §23.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please check your connection and try again.',
}) {
  if (error is PhotoStorageException) {
    return error.message;
  }

  if (error is FirebaseAuthException) {
    if (_userFacingAuthCodes.contains(error.code)) {
      return error.message ?? fallback;
    }

    return fallback;
  }

  return fallback;
}
