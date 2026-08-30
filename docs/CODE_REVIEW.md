# Baby Book — Code Review

Reviewed against `docs/PRODUCT_SPEC.md` (v2.0) as source of truth. Scope: everything
under `lib/`, `firestore.rules`, `firebase.json`, `pubspec.yaml`. `flutter analyze`
was run as part of this review (results in §9).

Note: `lib/features/home/home_screen.dart` and `lib/services/google_drive_service.dart`
have uncommitted changes at review time (silent-restore logic, "My albums" title).
The review covers the working tree as it currently stands, not just `HEAD`.

---

## 1. Spec alignment

- **Missing from the vertical slice (§21):** step 7–9 ("close and restart, see memory
  in correct position") is architecturally supported (Firestore + `orderBy(memoryDate)`)
  but untested per this review — no test suite exists. Everything else in §21 (steps
  1–12) has corresponding code. **Suggestion:** verify step 7–9 on a real device restart,
  not just hot reload.
- **Contradicts a closed decision (§24 "Data storage: cloud-first with local cache"):**
  no local cache/offline queue exists for photo uploads — `GoogleDriveService.uploadPhoto`
  is a bare network call with no queueing. Firestore itself has default SDK offline
  persistence, but Drive uploads do not. **Deviation.**
- **Silently resolves an open §10 question:** §10.2 lists "sign-in method" as open, but
  `auth_choice_screen.dart` only offers email/password — this is a de facto decision
  never recorded in §10. Google Sign-In is correctly reserved for Drive only, keeping
  the §9.2 identity separation intact (a good sign). **Deviation — record the decision
  or explicitly mark email/password as MVP-only.**
- **Silently resolves §10.2 "photo compression policy":** `google_drive_service.dart:317-318`
  fixes thumbnail width at 320px and JPEG quality 65, and uploads originals uncompressed,
  with no config surface. This is a real default, not documented in §10.2. **Deviation
  — record in the spec.**
- **§10.1 (photo storage) is still open in the spec but the app ships a full working
  Drive pipeline** (upload, download, delete, folder management) built on `drive.file`
  scope, which per §10.1 itself is suspected incompatible with shared books. Continued
  investment here is itself a soft resolution of a blocking open decision. **Deviation
  — see §3 below, this should block further Drive feature work until §10.1 is closed.**
- No `memberIds` field, invite flow, or co-parent UI exists (§11, §10.2). This matches
  the "open, not yet built" status — **not a violation**, just confirming it's still open.

---

## 2. Data model

- `Memory` (`lib/models/memory.dart`) correctly carries both `memoryDate` and
  `createdAt`, plus `updatedAt` and `hiddenFromBook`. **Matches §8.1.**
- `MemoryRepository.watchMemories` (`memory_repository.dart:90`) orders by
  `.orderBy('memoryDate')`, never `createdAt`. **Correct, matches the hard rule.**
- `createMemory` (`memory_repository.dart:31`) defaults `memoryDate` to
  `DateTime.now()` when not supplied. **Matches §8.1's "defaults to creation date."**
- `PhotoReference` (`lib/models/photo_reference.dart`) is a proper object (provider,
  file IDs, owner, dimensions), not a bare string. **Matches §8.3.**
- **Bug/risk — client clock used for `memoryDate` default:** `memory_repository.dart:31`
  uses local `DateTime.now()` for the default `memoryDate`, while `createdAt` uses
  `FieldValue.serverTimestamp()`. A phone with a wrong clock will silently misplace a
  memory in the timeline. **Suggestion:** default `memoryDate` server-side or reconcile
  against server time.
- **Deviation from §8.4 schema — no `memberIds`:** `Book` (`lib/models/book.dart`) only
  has `ownerIds`; the spec's conceptual schema separates `ownerIds`/`memberIds`. Today
  every collaborator would need to be in `ownerIds` (able to delete the whole book) to
  see it at all — there is no lesser "member" role. **Risk for multi-parent books** once
  co-parent sharing ships: adding a partner currently means granting delete rights too.
- **Deviation — no `schemaVersion`:** §8.4 explicitly asks to decide and document a
  schema evolution strategy "before real user data exists." No such field exists
  anywhere in the write paths. **Suggestion**, becomes urgent before shipping to real users.
- **Multiple books:** `BookRepository.watchMyBooks` queries `arrayContains: user.uid`
  on `ownerIds`, correctly supporting multiple books per account. **Matches §5/§6.**
- Firestore document reads use unchecked casts (`data['childName'] as String`,
  `data['createdBy'] as String`, etc.) throughout `book_repository.dart` and
  `memory_repository.dart` — a malformed or legacy document will throw inside the
  stream `.map()` and break the entire list for that user with no graceful fallback.
  **Risk**, especially once a `schemaVersion` migration happens.

---

## 3. Google Drive integration

- **Scope requested:** `drive.file` only (`google_drive_service.dart:15`). This is the
  minimum reasonable scope and matches §9.3's guidance if Drive stays in use.
- **Silent account restoration:** implemented in the current working tree
  (`connect()`, `google_drive_service.dart:149-198`) — it persists `driveAccountEmail`
  per Baby Book `uid` in Firestore, and uses `attemptLightweightAuthentication()` before
  falling back to an interactive prompt. This appears to resolve the CLAUDE.md
  "immediate known issue." **Should be verified on-device and committed**, since it's
  currently unstaged.
- **Bug/critical risk — breaks shared books (§10.1, §11):** `drive.file` scope grants
  access only to files an app created *for that Google account*. When Parent B's app
  calls `DriveImage`/`downloadPhoto` (`drive_image.dart:33`, `google_drive_service.dart:88`)
  for a photo Parent A uploaded, Parent B's Drive authorization will not have access to
  that file — the download will fail. **There is currently no code path that makes a
  photo visible across two different Google accounts.** This is exactly the scenario
  §10.1 flags as blocking, and it is not mitigated anywhere in the app. This should
  block further Drive feature work per the spec's own instruction.
- **Drive exposed in user-facing strings:** `uploadPhoto` throws
  `Exception('Google Drive did not return an original file ID')` and a similar message
  for thumbnails (`google_drive_service.dart:302`, `346`). These exceptions are caught
  in `memory_form_screen.dart:322` (`_errorMessage = e.toString()`) and rendered
  directly in the UI. **Deviation from §23** ("hide the infrastructure") — a failed
  upload can literally show the word "Google Drive" to the parent.
- **No caching layer:** `DriveImage` (`drive_image.dart`) re-issues a Drive API
  `files.get` download on every widget instantiation, with no disk/memory cache. Since
  `ListView.builder` recycles off-screen items, scrolling the timeline repeatedly
  re-downloads the same thumbnails. See §7 (performance) for cost/latency impact.
- **Dead code / unwired feature:** `deleteUploadedPhotos` and `changeAccount` are fully
  implemented but never called from any screen. See §8 for the durability consequence
  of `deleteUploadedPhotos` not being wired up.

---

## 4. Firebase/Firestore

- **Security rules exist** (`firestore.rules`) and correctly gate `users`, `books`, and
  `books/{bookId}/memories` on `request.auth` and `ownerIds` membership. **Matches §12**
  ("server-side... on every read and write") for Firestore specifically.
- **Gap — no schema/type validation in rules:** rules check authorization only, not
  document shape (e.g., nothing stops a client writing a `memoryDate` as a string, or an
  arbitrarily large `text` field). Not a spec violation per se, but a real risk once the
  app is public. **Suggestion.**
- **Bug/risk — Save can report success while photos are not durable:** In
  `memory_form_screen.dart:_saveMemory` (line 263), Drive uploads happen in a `for` loop
  *before* the Firestore write. If upload succeeds for photo 1 but throws on photo 2 (or
  the Firestore write itself then fails), the function throws, `createMemory`/
  `updateMemory` never runs, and the already-uploaded photo(s) are silently orphaned in
  Drive with **no Firestore document referencing them and no cleanup call**. This is
  precisely the "Upload succeeds, Firestore save fails" case §7.5 calls out for
  deliberate handling — it is currently unhandled. **Bug.**
- **Text/photo selections are not lost on failure** — the text controller and
  `_newPhotos`/`_existingPhotos` lists are untouched until save fully succeeds, so a
  failed save leaves the form intact for retry. **Matches §16's "must not lose entered
  text or selected photos."** Good.
- **Bug/risk — retries are not idempotent:** because the failed-upload photos above stay
  in `_newPhotos`, tapping Save again re-uploads them, creating duplicate Drive files.
  §16 explicitly requires mutating operations to "handle retries without creating
  duplicates." **Deviation.**
- `deleteBook` (`book_repository.dart:25`) batch-deletes all `memories` documents and
  the `books` document, but never calls `GoogleDriveService.deleteUploadedPhotos` for
  any of the deleted memories' photos. **Bug — orphans every photo in a deleted book,**
  contradicting §16 "avoid orphaned photo files."
- **No unprotected reads/writes were found** — every repository method checks
  `_auth.currentUser` client-side in addition to the server-side rules. Good defense in
  depth, though the client-side checks are redundant with rules and not load-bearing.

---

## 5. UX flow

- **Add Memory (§7.3):**
  - Date defaults to today and is optional — `_memoryDate` starts `null`, the ListTile
    shows "Date: Today" until touched (`memory_form_screen.dart:466-472`). **Matches.**
  - Text is free-form and not required if a photo exists; save validation
    (`_saveMemory`, line 266) requires at least text or one photo. **Matches.**
  - Multiple photo selection: `_imagePicker.pickMultiImage()` (line 239). **Matches.**
  - Selected photos are shown as thumbnails and removable before saving, both for
    newly-picked (`_newPhotos`, line 407-444) and already-saved photos when editing
    (`_existingPhotos`, line 365-406). **Matches.**
  - **No "Ideas (i)" prompts button exists anywhere in the codebase.** §7.3 lists this
    as an MVP row. **Missing feature**, not just an open decision.
  - Add Photos lives inside `MemoryFormScreen`, reached only from `BookScreen`'s FAB or
    tapping a memory — **not on the Home screen.** `HomeScreen` has no photo affordance
    at all. **Matches the explicit §7.3 rule and the rejected earlier attempt.**
- **Edit (§7.4):** `MemoryFormScreen` is reused for both Add and Edit via the optional
  `memory` constructor param (`memory_form_screen.dart:14-19`), not a separate screen.
  Text, date, and photos are all editable from the same form. **Matches.** However, §7.4
  calls for a **three-dot menu with Edit and Delete on the memory card**; the current
  `BookScreen` card has no menu at all — tapping the whole card opens the form, and
  Delete lives inside the form itself, not as a card-level action. **Deviation** — minor
  UX difference from the specified interaction, though functionally both actions exist.
- **Delete (§7.5):** confirmation dialog is present (`memory_form_screen.dart:76-96`).
  As covered in §4 above, the underlying Drive file cleanup is not performed —
  **deviation from the explicit "clean up associated photo files" instruction.**
- Home screen book cards use a three-dot (`PopupMenuButton`) with **Rename/Delete**
  (`home_screen.dart:175-192`) — this pattern matches what §7.4 asks for on memories but
  wasn't applied there; worth reusing on `BookScreen`'s memory cards for consistency.

---

## 6. RTL/Hebrew readiness

- **No RTL or Hebrew support exists anywhere in the app today.** This is a significant
  gap against §13 ("Build layouts RTL-capable from the start... not a later translation
  exercise") and the §4 principle "Hebrew is first-class."
- `main.dart`'s `MaterialApp` sets no `locale`, `localizationsDelegates`, or
  `supportedLocales` — Flutter has no basis to ever switch text direction.
- Hardcoded physical-direction layout that will visibly break under RTL:
  - `book_screen.dart:121` — `Icons.chevron_right` as a fixed "next" affordance; under
    RTL this should point left.
  - `memory_form_screen.dart:386-388` and `428-430` — `Positioned(right: 2, top: 2, ...)`
    for photo remove buttons; should use logical `Positioned.directional` /
    `AlignmentDirectional` so it flips under RTL.
  - `memory_form_screen.dart:357` — `Alignment.centerLeft` for the "Photos" label;
    should be `AlignmentDirectional.centerStart`.
  - Date strings are hand-formatted as `'${d.day}/${d.month}/${d.year}'` in three places
    (`book_screen.dart:116-118`, `create_book_screen.dart:100`,
    `memory_form_screen.dart:469-471`) with no locale-aware formatting — will not adapt
    to Hebrew numeral/date conventions per §13.
  - All UI strings are hardcoded English literals with no `intl`/localization package in
    `pubspec.yaml` at all.
- **This is not itself a "bug" today** (the MVP milestone in §21 doesn't require RTL
  yet), but per §13 and the CLAUDE.md milestone note, RTL is meant to be a foundation,
  not a retrofit — every screen built so far will need rework. **Flag as a growing
  deviation the longer it's deferred.**

---

## 7. Performance risks

- **Timeline image resolution:** `BookScreen` correctly prefers
  `photo.thumbnailFileId ?? photo.originalFileId` (`book_screen.dart:88-93`) and shows
  at most 5 previews (`.take(5)`, line 54) — close to the spec's "2-3" guidance, slightly
  over. If a photo is missing a thumbnail (fallback to `originalFileId`), the timeline
  would download a full-resolution image, silently violating the explicit "never render
  the timeline by downloading full-resolution images" rule. **Risk**, not yet a bug
  since `uploadPhoto` always generates a thumbnail today.
- **Unbounded queries:** `MemoryRepository.watchMemories` (`memory_repository.dart:85`)
  has no `.limit()` and no pagination — it's a live snapshot listener over the entire
  memories subcollection. `BookRepository.watchMyBooks` is similarly unbounded (fine at
  book scale, not fine at memory scale). **Deviation from §16** ("A timeline spanning
  years must stay fast via pagination and lazy loading").
- **No image caching:** `DriveImage` re-downloads from the Drive API on every widget
  build with no disk or memory cache (`drive_image.dart:33`). Scrolling a long timeline
  repeatedly re-fetches the same thumbnails — this will not hold up at "500+ memories,
  2000+ photos" and adds real Drive API quota/latency cost. **Risk.**
- **Synchronous, sequential photo upload blocks Save:** `_saveMemory`
  (`memory_form_screen.dart:280-290`) awaits each photo upload one at a time in a loop
  before the Firestore write, with the whole form locked (`_isLoading`) and no
  per-photo progress. §16 requires saving to "feel instant" with photo uploads
  continuing "in the background with a clear indicator" — the current implementation
  does neither for memories with photos. **Deviation.**
- No limit on how many photos can be selected in one memory (`pickMultiImage()` is
  unbounded) — a very large multi-select would serialize into a very long blocking
  upload loop. **Risk**, ties to the still-open §10.2 "max photos per memory" decision.

---

## 8. Error handling and durability

- **Network failure during Firestore save:** caught and surfaced as `_errorMessage`
  (`memory_form_screen.dart:318-325`); the memory is simply not created, no partial
  Firestore write is possible since it's a single `.set()`/`.update()` call. **Safe.**
- **Network failure during photo upload:** see §4 — can leave uploaded-but-unreferenced
  Drive files with no automatic or manual cleanup path exposed anywhere in the UI.
  **Bug**, one of the explicit §7.5 partial-failure cases.
- **No offline/retry queue** exists for photo uploads (§9.1's "local cache... save/
  upload queue" is not implemented for Drive, only Firestore's own SDK-level offline
  cache applies, and only to the metadata write, not the photo bytes).
- **Never report Save success before durable:** verified correct — `_saveMemory` only
  pops/exits after `await` on the repository call completes (`memory_form_screen.dart:
  294-317`). **Matches the hard rule.**
- **Partial failure — Firestore delete vs. Drive delete:** `deleteMemory`
  (`memory_repository.dart:67`) only deletes the Firestore document; it never attempts
  Drive cleanup, so this specific §7.5 case ("Firestore delete succeeds, photo store
  delete fails") can't even be tested — the Drive delete is never attempted in the first
  place. Same for `deleteBook`. **Bug**, same root cause as §4.
- Removing a photo from an existing memory during Edit (`_existingPhotos.remove(photo)`,
  `memory_form_screen.dart:395`) and then saving silently drops that photo from
  `photoRefs` without ever calling `deleteUploadedPhotos` for it — another orphan path.
  **Bug.**

---

## 9. Code quality

- **`flutter analyze`: 0 issues.** ("No issues found!", ran clean against
  `flutter_lints: ^6.0.0`.)
- **Dead code:** `GoogleDriveService.deleteUploadedPhotos` (`google_drive_service.dart:48`)
  and `GoogleDriveService.changeAccount` (`google_drive_service.dart:121`) are fully
  implemented but have zero call sites in the app. The first is a missing durability
  feature (§4/§8); the second is a missing "switch Google account" settings affordance
  that doesn't exist yet.
- **No TODO/FIXME comments** were found anywhere in `lib/`.
- **Naming inconsistency:** the root widget is still `MyFirstApp` (`main.dart:14`), and
  `auth_choice_screen.dart:19` literally displays **"My First App"** as the app title in
  the UI — the actual product name "Baby Book" never appears in-app. CLAUDE.md says not
  to spend time on branding yet, but this is user-visible, not just internal naming.
  **Suggestion**, low priority per project instructions.
- Repeated hand-rolled date formatting (`'${d.day}/${d.month}/${d.year}'`) is
  duplicated in three files instead of a shared helper — minor duplication, also the
  root of the RTL date-formatting gap in §6.
- Firestore document parsing uses unchecked `as` casts throughout the repositories
  (see §2) — consistent style, but no shared/tested "from Firestore" defensive layer.

---

## Fix-first priority list

1. **Resolve §10.1 (photo storage) before writing more Drive code.** `drive.file` scope
   cannot serve a photo to a second parent's account — this silently breaks the core
   §11 sharing requirement the moment co-parent access ships, and the spec itself says
   this should block further Drive investment.
2. **Wire up photo cleanup on delete/replace.** `deleteMemory`, `deleteBook`, and
   removing a photo during Edit all leave Drive files orphaned — `deleteUploadedPhotos`
   already exists and is simply never called. This is the highest-value, lowest-effort
   fix here (§4, §8).
3. **Handle the upload-succeeds/Firestore-fails partial failure.** Either roll back
   (delete) successfully uploaded photos when the Firestore write fails, or make retry
   idempotent by tracking already-uploaded photos instead of re-uploading them (§4, §8).
4. **Stop leaking "Google Drive" into user-facing error text.** Catch Drive-specific
   exceptions and rewrap them in neutral copy before they reach `_errorMessage` (§3, §23).
5. **Add pagination/limit to `watchMemories` and a caching layer to `DriveImage`.**
   Neither will hold up at the "500+ memories / 2000+ photos" scale the spec calls out,
   and the current implementation re-downloads every visible thumbnail on every scroll
   (§7).

RTL/Hebrew readiness (§6) is a real and growing gap but is explicitly post-vertical-slice
work per §21 — sequence it right after the fix-first list above, not before it.
