# Migration Checklist

Moving the Baby Book project to a new machine.
Audited 2026-11-04 from the original Windows 11 machine.

## 1. Toolchain versions on the original machine

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.44.9 | channel `stable`, revision 6b182d2c75 |
| Dart | 3.12.2 | ships with the above |
| DevTools | 2.57.0 | |
| Node.js | v22.23.2 | must stay on 22.x — `functions/package.json` pins `"node": "22"` |
| npm | 10.9.8 | |
| Firebase CLI | 15.28.2 | installed via npm (global) |
| FlutterFire CLI | 1.4.1 | `dart pub global activate flutterfire_cli` |
| Gradle | 9.3.1 | via `android/gradle/wrapper` — no manual install |
| Android Gradle Plugin | 9.1.0 | declared in `android/settings.gradle.kts` |
| Kotlin | 2.4.0 | declared in `android/settings.gradle.kts` |
| Java / JVM target | 17 | Android Studio's bundled JDK is sufficient |
| Android SDK | 37.0.0 | |
| firebase-functions | ^6.0.0 | |
| firebase-admin | ^12.0.0 | |

The Flutter SDK was vendored at `C:\Baby_App\flutter` rather than installed
system-wide, and `flutter` resolved to `C:\Baby_App\flutter\bin\flutter.bat`.

## 2. Setup steps on the new machine

1. Install Flutter 3.44.9 on the **stable** channel. Verify: `flutter --version`.
2. Install Node 22.x, then `npm i -g firebase-tools@15.28.2`.
3. `dart pub global activate flutterfire_cli 1.4.1`.
4. Install Android Studio; accept licenses (`flutter doctor --android-licenses`).
5. Clone the repo: `git clone https://github.com/yair-naor1/my-baby-App.git`.
6. Set the git identity before the first commit:
   `git config --global user.email "ynaor12@gmail.com"`
   `git config --global user.name "yair-naor1"`
7. `flutter pub get` and `cd functions && npm install`.
8. `firebase login` as ynaor12@gmail.com, then `firebase use my-baby-app-dev`.
9. Run `flutter analyze`, then the §21 vertical-slice smoke test.

## 3. Nothing to hand-carry from the repo

`google-services.json`, `lib/firebase_options.dart`, `.firebaserc`,
`firebase.json` and `firestore.rules` are all tracked in git, so a clone
restores a working Firebase configuration. There are no `.env` files, no
release keystore, and no service-account JSON on the original machine.

Cloudflare R2 credentials live in Firebase Secret Manager under
`my-baby-app-dev` (`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`) and are reachable from any machine
once logged in: `firebase functions:secrets:access R2_ACCOUNT_ID`.
Vertex AI uses the Cloud Function's own service account — no key needed.

## 4. Back up separately (outside git)

- `My_First_App_PRD_v1.0.docx` — the original product requirements document
- `pitch.docx`
- Optional: `~/.claude/projects/` session transcripts and `~/.claude/history.jsonl`

## 5. Known gaps carried forward

- Release builds sign with **debug** keys (`android/app/build.gradle.kts:36-39`).
  A real upload keystore must be generated before any Play Store release; none
  exists yet, so there is nothing to migrate.
- `applicationId` is still `com.example.my_app`.
- Windows desktop target needs Visual Studio with the "Desktop development
  with C++" workload; it was never installed, and Android was the test target.
