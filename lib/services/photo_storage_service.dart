import 'dart:io';
import 'dart:typed_data';

import '../models/photo_reference.dart';

/// A storage-layer failure, already safe to show to the parent.
///
/// Never leaks provider-specific wording (e.g. "Google Drive") — callers can
/// display [message] directly without violating the "hide the infrastructure"
/// UX rule.
class PhotoStorageException implements Exception {
  const PhotoStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where memory photos actually live.
///
/// The concrete provider (Google Drive today) is an open product decision —
/// see PRODUCT_SPEC.md §10.1. Everything outside this file talks to
/// [PhotoStorageService], never to a concrete provider, so swapping the
/// provider later touches one implementation, not every screen.
abstract class PhotoStorageService {
  Future<PhotoReference> uploadPhoto({
    required String bookId,
    required File photo,
    required String fileName,
  });

  Future<Uint8List> downloadPhoto(String fileId);

  /// Deletes every underlying file for [photos]. Best-effort per file —
  /// callers should not assume every file was removed, only that this
  /// completed without throwing for connectivity/auth failures.
  Future<void> deletePhotos(List<PhotoReference> photos);
}
