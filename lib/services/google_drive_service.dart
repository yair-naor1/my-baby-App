import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/photo_reference.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class GoogleDriveService {
  static const _serverClientId =
      '761925234385-d1lujprjq4uo6ugddgt0tuugte9gkf30.apps.googleusercontent.com';

  static const _scopes = <String>['https://www.googleapis.com/auth/drive.file'];

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static Future<void>? _initialization;
  static GoogleSignInAccount? _currentAccount;

  Future<void> _ensureInitialized() {
    return _initialization ??= _googleSignIn.initialize(
      serverClientId: _serverClientId,
    );
  }

  Future<void> clearSession() async {
    await _ensureInitialized();

    await _googleSignIn.signOut();
    _currentAccount = null;
  }

  Future<void> deleteUploadedPhotos(List<PhotoReference> photos) async {
    if (photos.isEmpty) return;

    final account = await connect();

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    final client = authorization.authClient(scopes: _scopes);

    final driveApi = drive.DriveApi(client);

    try {
      for (final photo in photos) {
        await _tryDeleteDriveFile(driveApi, photo.thumbnailFileId);

        await _tryDeleteDriveFile(driveApi, photo.originalFileId);
      }
    } finally {
      client.close();
    }
  }

  Future<void> _tryDeleteDriveFile(
    drive.DriveApi driveApi,
    String? fileId,
  ) async {
    if (fileId == null) return;

    try {
      await driveApi.files.delete(fileId);
    } catch (_) {
      // Cleanup failure should not hide the original upload error.
    }
  }

  Future<Uint8List> downloadPhoto(String fileId) async {
    final account = await connect();

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    final client = authorization.authClient(scopes: _scopes);
    final driveApi = drive.DriveApi(client);

    try {
      final media =
          await driveApi.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final bytes = <int>[];

      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  Future<GoogleSignInAccount> changeAccount() async {
    await _ensureInitialized();

    await _googleSignIn.signOut();
    _currentAccount = null;

    final account = await _googleSignIn.authenticate(scopeHint: _scopes);

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    _currentAccount = account;

    return account;
  }

  Future<GoogleSignInAccount> connect() async {
    await _ensureInitialized();

    var account = _currentAccount;

    if (account == null) {
      final lightweightAuth = _googleSignIn.attemptLightweightAuthentication();

      if (lightweightAuth != null) {
        account = await lightweightAuth;
      }
    }

    account ??= await _googleSignIn.authenticate(scopeHint: _scopes);

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    _currentAccount = account;

    return account;
  }

  Future<String> _getOrCreateRootFolder(drive.DriveApi driveApi) async {
    final result = await driveApi.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' "
          "and appProperties has { key='babyBookRoot' and value='true' } "
          "and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = 'Baby Book'
      ..mimeType = 'application/vnd.google-apps.folder'
      ..appProperties = {'babyBookRoot': 'true'};

    final created = await driveApi.files.create(folder, $fields: 'id');

    return created.id!;
  }

  Future<String> _getOrCreateBookFolder(
    drive.DriveApi driveApi,
    String bookId,
  ) async {
    final rootFolderId = await _getOrCreateRootFolder(driveApi);

    final result = await driveApi.files.list(
      q:
          "'$rootFolderId' in parents "
          "and mimeType = 'application/vnd.google-apps.folder' "
          "and appProperties has { key='bookId' and value='$bookId' } "
          "and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = bookId
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [rootFolderId]
      ..appProperties = {'bookId': bookId};

    final created = await driveApi.files.create(folder, $fields: 'id');

    return created.id!;
  }

  Future<PhotoReference> uploadPhoto({
    required String bookId,
    required File photo,
    required String fileName,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      throw Exception('User is not logged in');
    }

    final account = await connect();

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    final client = authorization.authClient(scopes: _scopes);
    final driveApi = drive.DriveApi(client);
    String? originalFileId;
    String? thumbnailFileId;
    try {
      final bookFolderId = await _getOrCreateBookFolder(driveApi, bookId);

      // ---- Upload original ----

      final originalMetadata = drive.File()
        ..name = fileName
        ..parents = [bookFolderId]
        ..appProperties = {
          'bookId': bookId,
          'ownerUid': firebaseUser.uid,
          'variant': 'original',
        };

      final originalMedia = drive.Media(photo.openRead(), await photo.length());

      final uploadedOriginal = await driveApi.files.create(
        originalMetadata,
        uploadMedia: originalMedia,
        $fields: 'id,name',
      );

      if (uploadedOriginal.id == null) {
        throw Exception('Google Drive did not return an original file ID');
      }

      originalFileId = uploadedOriginal.id;

      // ---- Create thumbnail ----

      final originalBytes = await photo.readAsBytes();
      final decodedImage = img.decodeImage(originalBytes);

      if (decodedImage == null) {
        throw Exception('Could not read image');
      }

      final thumbnailImage = img.copyResize(decodedImage, width: 320);

      final thumbnailBytes = img.encodeJpg(thumbnailImage, quality: 65);

      final dotIndex = fileName.lastIndexOf('.');
      final baseName = dotIndex > 0
          ? fileName.substring(0, dotIndex)
          : fileName;

      final thumbnailMetadata = drive.File()
        ..name = '${baseName}_thumbnail.jpg'
        ..parents = [bookFolderId]
        ..appProperties = {
          'bookId': bookId,
          'ownerUid': firebaseUser.uid,
          'variant': 'thumbnail',
        };

      final thumbnailMedia = drive.Media(
        Stream.value(thumbnailBytes),
        thumbnailBytes.length,
      );

      final uploadedThumbnail = await driveApi.files.create(
        thumbnailMetadata,
        uploadMedia: thumbnailMedia,
        $fields: 'id,name',
      );

      if (uploadedThumbnail.id == null) {
        throw Exception('Google Drive did not return a thumbnail file ID');
      }

      thumbnailFileId = uploadedThumbnail.id;

      return PhotoReference(
        provider: 'googleDrive',
        originalFileId: uploadedOriginal.id!,
        thumbnailFileId: uploadedThumbnail.id!,
        ownerUid: firebaseUser.uid,
      );
    } catch (e) {
      await _tryDeleteDriveFile(driveApi, thumbnailFileId);

      await _tryDeleteDriveFile(driveApi, originalFileId);

      rethrow;
    } finally {
      client.close();
    }
  }
}
