import 'package:google_sign_in/google_sign_in.dart';

/// The Google identity provider behind "Sign in with Google" (spec §9.2).
///
/// This used to also manage Google Drive access (Drive was the photo store
/// before the Cloudflare R2 migration, spec §9.3) — that meant requesting
/// the `drive.file` OAuth scope as part of sign-in, plus a whole silent
/// restore subsystem to keep a Drive-scoped token alive across app launches.
/// None of that is needed once nothing calls the Drive API: this is now a
/// plain identity sign-in, and Firebase Auth's own persisted session is what
/// keeps the user logged in across launches — no custom restore logic
/// required here.
class GoogleAuthService {
  static const _serverClientId =
      '761925234385-d1lujprjq4uo6ugddgt0tuugte9gkf30.apps.googleusercontent.com';

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static Future<void>? _initialization;

  Future<void> _ensureInitialized() {
    return _initialization ??= _googleSignIn.initialize(
      serverClientId: _serverClientId,
    );
  }

  /// No-op today: [signInInteractively] already forces a fresh session via
  /// its own `signOut()` before `authenticate()`, so there's no cached state
  /// left here to invalidate on logout. Kept as a real method so callers
  /// don't need to know that — logout should always be allowed to assume
  /// "clear whatever this service is holding" without caring what that is.
  Future<void> clearSession() async {}

  /// Signs in interactively (shows the Google account picker). Used both by
  /// [AuthRepository.signInWithGoogle] (initial sign-in) and its "Link
  /// Google Account" flow.
  Future<GoogleSignInAccount> signInInteractively() async {
    await _ensureInitialized();

    // A plain signOut() here isn't enough: the Credential-Manager-backed
    // authenticate() can still silently hand back the exact same cached ID
    // token as before, since signOut() only clears this plugin's local
    // session pointer, not the underlying Android-level authorization.
    // Reusing the identical token gets rejected by Firebase's backend as
    // already consumed — confirmed on-device as a reproducible
    // FirebaseAuthException PROVIDER_ALREADY_LINKED even from a plain
    // signInWithCredential, not just linkWithCredential, on every retry
    // (2026-09-07). disconnect() actually revokes the prior authorization,
    // forcing a genuinely fresh token on the next authenticate() call. This
    // is safe now that no silent-restore-on-launch logic depends on
    // preserved Credential Manager state (Firebase Auth's own persisted
    // session covers "stay logged in" instead) — see the class doc comment.
    await _googleSignIn.disconnect();

    return _googleSignIn.authenticate();
  }
}
