import 'package:cloud_functions/cloud_functions.dart';

/// Calls the `joinBook` Cloud Function (spec §11) — the only way a second
/// uid ever gets into a book's `ownerIds`, since Firestore rules require the
/// caller to already be an owner to update a book (a brand-new joiner can't
/// add themselves with a plain client write). See functions/bookSharing.js
/// for the actual authorization/write.
class BookSharingService {
  final _functions = FirebaseFunctions.instance;

  /// [bookId] is the share code (spec §11: the book's own id doubles as an
  /// unguessable, non-expiring invite code — no separate code generation).
  /// Returns the child's name on success, so the caller can confirm they
  /// joined that child's book. Throws [FirebaseFunctionsException] — see
  /// friendlyErrorMessage, which already surfaces this function's messages
  /// (e.g. "That code doesn't match any book.") directly.
  Future<String> joinBook(String bookId) async {
    final callable = _functions.httpsCallable('joinBook');

    final result = await callable.call<Map<String, dynamic>>({
      'bookId': bookId,
    });

    return result.data['childName'] as String;
  }
}
