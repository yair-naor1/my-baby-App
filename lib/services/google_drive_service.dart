import 'package:google_sign_in/google_sign_in.dart';
import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/photo_reference.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'photo_storage_service.dart';

class GoogleDriveService implements PhotoStorageService {
  static const _serverClientId =
      '761925234385-d1lujprjq4uo6ugddgt0tuugte9gkf30.apps.googleusercontent.com';

  static const _scopes = <String>['https://www.googleapis.com/auth/drive.file'];

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void>? _initialization;
  static GoogleSignInAccount? _currentAccount;

  // Which Firebase uid _currentAccount was resolved for. connect() only
  // trusts the cached account when this still matches the signed-in Baby
  // Book user — otherwise a second Baby Book user on the same device/app
  // process could inherit the first user's Drive account.
  static String? _currentAccountForUid;

  // A single in-flight authentication is shared by every concurrent caller
  // instead of each one re-authenticating independently (previously, N
  // photos loading at once meant N redundant sign-in round trips).
  static Future<GoogleSignInAccount>? _connecting;

  // Reused across calls so N photo operations share one authenticated HTTP
  // connection instead of paying a fresh TLS handshake + token fetch per
  // photo. Invalidated whenever the account changes or a request fails.
  static http.Client? _cachedClient;
  static drive.DriveApi? _cachedDriveApi;

  Future<String?> _getSavedDriveEmail(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();

    return doc.data()?['driveAccountEmail'] as String?;
  }

  Future<void> _saveDriveEmail({
    required String uid,
    required String email,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'driveAccountEmail': email,
    }, SetOptions(merge: true));
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _googleSignIn.initialize(
      serverClientId: _serverClientId,
    );
  }

  Future<void> clearSession() async {
    _currentAccount = null;
    _currentAccountForUid = null;
    _invalidateClientCache();
  }

  void _invalidateClientCache() {
    _cachedClient?.close();
    _cachedClient = null;
    _cachedDriveApi = null;
  }

  @override
  Future<void> deletePhotos(List<PhotoReference> photos) async {
    if (photos.isEmpty) return;

    try {
      final driveApi = await _getDriveApi();

      for (final photo in photos) {
        await _tryDeleteDriveFile(driveApi, photo.thumbnailFileId);

        await _tryDeleteDriveFile(driveApi, photo.originalFileId);
      }
    } catch (e) {
      _throwStorageError(e, 'Could not remove one or more photos.');
    }
  }

  /// Wraps any thrown error in a [PhotoStorageException] with UI-safe text,
  /// so no Drive-specific wording ever reaches a screen (spec §23). Also
  /// drops the cached client, so a stale/expired token doesn't keep failing
  /// silently on every subsequent call.
  Never _throwStorageError(Object error, String fallbackMessage) {
    _invalidateClientCache();

    if (error is PhotoStorageException) throw error;

    throw PhotoStorageException(fallbackMessage);
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

  @override
  Future<Uint8List> downloadPhoto(String fileId) async {
    try {
      final driveApi = await _getDriveApi();

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
    } catch (e) {
      _throwStorageError(e, 'Could not load this photo. Please try again.');
    }
  }

  /// Signs in interactively (shows the Google account picker) and requests
  /// the Drive scope in the same consent step, so a fresh sign-in never
  /// needs a second prompt later for photo access. Used both by
  /// [changeAccount] and by the unified "Sign in with Google" flow in
  /// AuthRepository.
  Future<GoogleSignInAccount> signInInteractively() async {
    await _ensureInitialized();

    // Without this, the newer Credential-Manager-backed authenticate() can
    // silently hand back a cached session/token instead of doing a fresh
    // OAuth exchange. If that reused token was already consumed by an
    // earlier linkWithCredential call, Firebase's backend rejects it as
    // already used (surfaces as FirebaseAuthException PROVIDER_ALREADY_LINKED
    // even from a plain signInWithCredential). Forcing a fresh session here
    // — same fix changeAccount() already applies — avoids that collision.
    await _googleSignIn.signOut();

    final account = await _googleSignIn.authenticate(scopeHint: _scopes);

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    _currentAccount = account;
    _currentAccountForUid = null;
    _invalidateClientCache();

    return account;
  }

  /// Remembers the currently-authenticated Google account as [uid]'s Drive
  /// account, so [connect] can restore it silently on later launches (and
  /// immediately reuse it this session) without a second authorization
  /// prompt. Call this once the Baby Book identity for the sign-in is known.
  Future<void> rememberSignedInAccountFor(String uid) async {
    final account = _currentAccount;

    if (account == null) return;

    _currentAccountForUid = uid;

    await _saveDriveEmail(uid: uid, email: account.email);
  }

  Future<GoogleSignInAccount> changeAccount() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      throw Exception('User is not logged in');
    }

    await _ensureInitialized();
    await _googleSignIn.signOut();

    final account = await signInInteractively();

    await rememberSignedInAccountFor(firebaseUser.uid);

    return account;
  }

  Future<GoogleSignInAccount> connect() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      throw Exception('User is not logged in');
    }

    // Already resolved for this exact Baby Book user this session — skip
    // the Firestore lookup and re-authentication entirely.
    if (_currentAccount != null && _currentAccountForUid == firebaseUser.uid) {
      return _currentAccount!;
    }

    return _connecting ??= _connectSlow(firebaseUser.uid).whenComplete(() {
      _connecting = null;
    });
  }

  Future<GoogleSignInAccount> _connectSlow(String uid) async {
    await _ensureInitialized();

    final savedEmail = await _getSavedDriveEmail(uid);
    GoogleSignInAccount? account;

    if (savedEmail != null) {
      final lightweightAuth = _googleSignIn.attemptLightweightAuthentication();

      if (lightweightAuth != null) {
        final restoredAccount = await lightweightAuth;

        if (restoredAccount != null && restoredAccount.email == savedEmail) {
          account = restoredAccount;
        }
      }
    }

    // No saved account, or Google restored the wrong user's account.
    if (account == null) {
      await _googleSignIn.signOut();

      account = await _googleSignIn.authenticate(scopeHint: _scopes);

      await _saveDriveEmail(uid: uid, email: account.email);
    }

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    _currentAccount = account;
    _currentAccountForUid = uid;
    _invalidateClientCache();

    return account;
  }

  /// A Drive API client authenticated as the current account, reused across
  /// calls instead of opening a fresh HTTP connection (and paying a new TLS
  /// handshake + token fetch) for every photo.
  Future<drive.DriveApi> _getDriveApi() async {
    final account = await connect();

    final cached = _cachedDriveApi;
    if (cached != null) return cached;

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    final client = authorization.authClient(scopes: _scopes);
    final driveApi = drive.DriveApi(client);

    _cachedClient = client;
    _cachedDriveApi = driveApi;

    return driveApi;
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

    final driveApi = await _getDriveApi();
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
      final originalWidth = decodedImage.width;
      final originalHeight = decodedImage.height;
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
        width: originalWidth,
        height: originalHeight,
      );
    } catch (e) {
      await _tryDeleteDriveFile(driveApi, thumbnailFileId);

      await _tryDeleteDriveFile(driveApi, originalFileId);

      _throwStorageError(
        e,
        'Could not save the photo. Please check your connection and try again.',
      );
    }
  }
}
