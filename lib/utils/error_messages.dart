import 'package:firebase_auth/firebase_auth.dart';

import '../services/photo_storage_service.dart';

/// Turns any thrown error into text that is safe to show a parent.
///
/// Never surfaces raw provider/internal detail (Drive, Firestore error
/// codes, stack-trace-shaped text) — see PRODUCT_SPEC.md §23. Firebase Auth
/// errors are the one exception: their messages are already written for end
/// users (e.g. "The password is invalid").
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please check your connection and try again.',
}) {
  if (error is PhotoStorageException) {
    return error.message;
  }

  if (error is FirebaseAuthException) {
    return error.message ?? fallback;
  }

  return fallback;
}
