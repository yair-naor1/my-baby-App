import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/photo_reference.dart';
import 'photo_storage_service.dart';

/// Stores photo bytes in Cloudflare R2 (PRODUCT_SPEC.md §9.3), replacing
/// Google Drive. Never talks to R2 directly — every upload/download/delete
/// goes through a Cloud Function signing backend (`functions/r2Storage.js`)
/// that checks Firestore book membership and hands back short-lived
/// presigned URLs. This class never sees an R2 credential.
class R2PhotoStorageService implements PhotoStorageService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Without this, a stalled connection (weak signal, a dropped packet R2
  // never gets to retry) leaves the raw http.put/get call awaiting forever —
  // package:http sets no default timeout at all. Bounded here so a bad
  // connection surfaces as a normal, retriable error instead of an infinite
  // spinner (found on-device: a birth-photo upload hung mid-book-creation
  // with zero further network activity, no exception ever thrown).
  static const _networkTimeout = Duration(seconds: 90);

  Never _throwStorageError(Object error, String fallbackMessage) {
    if (error is PhotoStorageException) throw error;

    throw PhotoStorageException(fallbackMessage);
  }

  String _extensionOf(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex <= 0 || dotIndex == fileName.length - 1) return 'jpg';

    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  @override
  Future<PhotoReference> uploadPhoto({
    required String bookId,
    required File photo,
    required String fileName,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      throw Exception('User is not logged in');
    }

    String? originalKey;
    String? thumbKey;

    try {
      final originalBytes = await photo.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);

      if (decodedImage == null) {
        throw Exception('Could not read image');
      }

      final originalWidth = decodedImage.width;
      final originalHeight = decodedImage.height;
      final thumbnailImage = img.copyResize(decodedImage, width: 320);
      final thumbnailBytes = img.encodeJpg(thumbnailImage, quality: 65);

      final callable = _functions.httpsCallable('getPhotoUploadUrls');

      final result = await callable.call<Map<String, dynamic>>({
        'bookId': bookId,
        'extension': _extensionOf(fileName),
      });

      originalKey = result.data['originalKey'] as String;
      thumbKey = result.data['thumbKey'] as String;

      final originalUploadUrl = result.data['originalUploadUrl'] as String;
      final thumbUploadUrl = result.data['thumbUploadUrl'] as String;

      final originalResponse = await http
          .put(Uri.parse(originalUploadUrl), body: originalBytes)
          .timeout(_networkTimeout);

      if (originalResponse.statusCode < 200 ||
          originalResponse.statusCode >= 300) {
        throw Exception(
          'Original upload failed (${originalResponse.statusCode})',
        );
      }

      final thumbResponse = await http
          .put(Uri.parse(thumbUploadUrl), body: thumbnailBytes)
          .timeout(_networkTimeout);

      if (thumbResponse.statusCode < 200 || thumbResponse.statusCode >= 300) {
        throw Exception('Thumbnail upload failed (${thumbResponse.statusCode})');
      }

      return PhotoReference(
        provider: 'r2',
        originalFileId: originalKey,
        thumbnailFileId: thumbKey,
        ownerUid: firebaseUser.uid,
        width: originalWidth,
        height: originalHeight,
      );
    } catch (e) {
      final keysUploaded = [?originalKey, ?thumbKey];

      if (keysUploaded.isNotEmpty) {
        try {
          await _deleteKeys(keysUploaded);
        } catch (_) {
          // Cleanup failure should not hide the original upload error.
        }
      }

      _throwStorageError(
        e,
        'Could not save the photo. Please check your connection and try again.',
      );
    }
  }

  @override
  Future<Uint8List> downloadPhoto(String fileId) async {
    try {
      final callable = _functions.httpsCallable('getPhotoDownloadUrl');

      final result = await callable.call<Map<String, dynamic>>({
        'key': fileId,
      });

      final downloadUrl = result.data['downloadUrl'] as String;

      final response = await http
          .get(Uri.parse(downloadUrl))
          .timeout(_networkTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (${response.statusCode})');
      }

      return response.bodyBytes;
    } catch (e) {
      _throwStorageError(e, 'Could not load this photo. Please try again.');
    }
  }

  Future<void> _deleteKeys(List<String> keys) async {
    if (keys.isEmpty) return;

    final callable = _functions.httpsCallable('deletePhotos');

    await callable.call<Map<String, dynamic>>({'keys': keys});
  }

  @override
  Future<void> deletePhotos(List<PhotoReference> photos) async {
    if (photos.isEmpty) return;

    final keys = [
      for (final photo in photos) ...[
        photo.originalFileId,
        if (photo.thumbnailFileId != null) photo.thumbnailFileId!,
      ],
    ];

    try {
      await _deleteKeys(keys);
    } catch (e) {
      _throwStorageError(e, 'Could not remove one or more photos.');
    }
  }
}
