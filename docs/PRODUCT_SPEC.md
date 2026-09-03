# Baby Book — Product & Engineering Specification

**Version 2.0 — supersedes "My First App PRD v1.0" and the ChatGPT handoff document.**

This is the single source of truth. When something here conflicts with an older
document, this file wins. When this file conflicts with the actual Git repository,
inspect the repository first — code may have moved ahead of the spec — then update
this file so it stops being wrong.

Documentation language is English, even though the app itself is bilingual.

---

## 1. Product identity

**Product name:** Baby Book

The repository and Flutter root class may still use `my_app` / `MyFirstApp`.
That is legacy naming, not the product name. Do not spend time on branding
until it is needed for release.

Likely logo direction: a pastel smiling baby face inside a rounded book/album icon.

---

## 2. Vision

Baby Book lets parents document a child's first year without ever "working on an album."

When something happens that is worth remembering — a milestone, a funny sentence,
a small moment, or just a photo — the parent opens the child's book, taps **Add**,
saves, and gets on with life.

The app keeps every memory in chronological order. Later, and especially around the
child's first birthday, it assembles those memories into a designed album that the
parent can review, edit, and export to PDF. The same book can then continue past the
first year into a childhood timeline.

**Guiding principle:** *The parent creates the memories. The app stores them and
presents them beautifully.*

**The question to ask for any product or engineering decision:**
> Does this make it easier and safer for a parent to capture a memory now and still
> have it years later?

---

## 3. The problem

- Traditional baby albums require the parent to remember to fill in pages and
  prompts at the right time.
- Photos scatter across the phone gallery; memories end up in WhatsApp, in notes,
  or forgotten entirely.
- Building an album at the end of the year is a large project: selecting photos,
  ordering them, writing, designing.
- Parents want to keep moments that have no matching photo — a sentence, a story,
  a small memory.

---

## 4. Product principles

| Principle | Meaning |
|---|---|
| Simplicity above all | The most important action in the product is **Add → Text / Photos → Save**. |
| Capture first, organize later | The parent never picks a category, page, or chapter while capturing. |
| AI is enhancement, not core | AI may help with album layout and fitting content to pages. It is never how the parent uses the product. |
| The memory belongs to the parent | AI must not invent meaningful captions or rewrite in a way that replaces the parent's voice. |
| Editable, not final | The generated book is a strong starting point, not a fixed result. |
| Hebrew is first-class | Full Hebrew support: UI, RTL, typography, and albums that read right-to-left. |
| Hide the infrastructure | The parent is creating memories, not managing cloud storage. |
| Durability over cleverness | Baby memories cannot be recreated. Prefer boring and reliable. |
| Users own their own ongoing costs, wherever realistic | The operator should not centrally pay for every user's resource usage as the base grows — applies to photo storage (§9.3: Drive/R2) and AI (§15/§10.2) alike. Where a genuinely user-owned mechanism isn't currently possible, prefer the cheapest operator-covered stopgap over building nothing, but treat it as temporary, not the destination. |

---

## 5. Target audience

Primary: parents of a newly born child or a child in their first year. The typical
user wants to document, but does not enjoy album design or keeping a tidy journal.

- A single parent managing the book.
- Two parents/partners documenting the same child together.
- A family with more than one child — a separate book per child.

---

## 6. MVP scope

| Capability | In MVP | Note |
|---|---|---|
| Account creation / sign-in | Yes | Basis for secure storage and cross-device sync |
| Create a book for a child | Yes | Name, birth date, basic birth details |
| Multiple books per account | Yes | One book per child |
| Add a free-form memory | Yes | Text, photos, or both |
| Edit / delete a memory | Yes | Including changing the date |
| Chronological memory list | Yes | Ordered by memory date, not entry time |
| Ideas / info button | Yes | Optional prompts only, never required |
| Monthly reminder | Yes | "\<child\> is X months old! What's new?" |
| Book partner / co-parent | Yes | Both parents can add and edit |
| Automatic album generation | Yes | Chronological ordering + smart layout |
| Edit the album before export | Yes | Content, photos, reordering |
| PDF export | Yes | Ready to view and print |
| Hebrew + English | Yes | Including full RTL |
| Video | No | Roadmap |
| Ordering a printed book in-app | No | Future print-house integration |
| AI story writing | No | Not part of the core experience |

---

## 7. User experience and flows

### 7.1 Creating a book

After signing up, the user creates a book and enters at minimum the **child's name**
and **birth date**. Optional fields may include birth place, birth time, weight at
birth, the birth story, and a cover photo. Birth height was tried and dropped
(2026-09-03) — not a relevant detail for this product.

Do not hard-code the app around exactly one child or one book. The Home screen is a
list of books, normally one per child.

**Implemented UI direction:** one form handles both create and edit (same
Add/Edit-reuses-one-form pattern as §7.4), reachable after creation via each book's
"Edit Book Info" menu item. The optional birth photos are a single gallery — the
cover photo isn't a separate upload, it's whichever birth photo the parent taps a
star on (defaults to the first one added if none is chosen).

Also has an optional child-gender field (boy/girl/prefer not to say) — this is
**not a product-facing field**, it's never displayed as a label anywhere. Its
only purpose is getting Hebrew grammatical gender agreement right in AI text
enhancement (§15); the form copy says so explicitly rather than asking for
gender as if it were its own meaningful question.

### 7.2 Book screen (the timeline)

This is the main day-to-day screen. The child/book appears at the top, the memory
list in the middle, and a prominent, always-reachable **Add** button.

- Chronological list of all memories.
- Every card renders at the same fixed height regardless of how much text or how
  many photos the memory has, so the timeline reads as a uniform list rather than
  cards that grow with content.
- Each item shows: memory date, a short text preview if there is text (or a plain
  "Photo memory" placeholder if there is only photos), and a single small photo
  thumbnail if there are photos, with a "+N" badge when there is more than one —
  not a row of previews, so photo count never changes the card's size.
- A photo-less card shows a small placeholder icon in the same thumbnail slot
  instead of collapsing, keeping every card's layout identical.
- Tapping an item opens it directly in the Edit Memory form (§7.4). A dedicated
  delete icon on the card itself handles Delete (§7.5) — no intermediate detail
  view or menu.
- Add is reachable without passing through a questionnaire or wizard.
- **Options menu (⋮), app bar, top right.** Single menu, not scattered icons —
  consolidated 2026-09-03 from two places (a standalone Ideas icon here, plus
  Edit/Rename/Delete that used to live on each book's card on the Home screen)
  after the user asked for them to live together. Contents, top to bottom:
  **Ideas**, **Album** (§14), **Album Settings** (stub), **Printing Guide**
  (stub), **Share Album** (stub, will route to §11's invite flow once built),
  divider, **Edit Book Info**, **Rename Book**, **Delete Book**. The book
  screen watches its book live (`BookRepository.watchBook`) so a rename/edit
  from this menu reflects immediately without reopening the screen.
- **Ideas**, opened from that menu, is a bank of ~100 age-tagged capture
  prompts across 14 categories (English + Hebrew). Two-level browse: tap the
  entry to see the 14 category headlines, tap one to see that category's
  prompts (most age-relevant-now ones sorted first, done-first reversed —
  order is frozen at screen-open time so a tap never reshuffles the list
  mid-browse). Tapping a prompt marks it "already captured" in place — a grey,
  animated strikethrough, per book, never inferred from memory content, never
  removed from view — **it does not navigate anywhere**, so browsing ideas
  can't interrupt writing a memory (an earlier version opened Add Memory on
  tap; changed after trying it). Placed on this screen rather than as an
  in-Add-Memory overlay (the original spec sketch) because age-relevance needs
  to know which book/child it's for.

**Performance rule:** a timeline card downloads and renders only a single small,
low-resolution thumbnail per memory (never more, regardless of photo count). The
full memory view shows all photos. Never render the timeline by downloading
full-resolution images.

### 7.3 Add Memory

The screen must stay minimal.

| Field / action | Behavior |
|---|---|
| Date | Defaults to today. Choosing a different date is **optional** — the parent must never be forced through a date picker for a normal memory. |
| Text box | Free text. Not required if at least one photo is attached. |
| Add photos | Select one or more photos from the phone or camera. Multiple selection must be supported. |
| Selected photos | Shown as thumbnails; the user can remove one before saving. |
| Save | Persists the memory and shows it in the list. |
| Cancel | Exits without saving; warn only if content was already entered. |
| Ideas (i) | See §7.2 — the ⓘ moved to the book screen's app bar, not an overlay here. |

At least some meaningful content (text or a photo) must exist before saving.

**Add Photos belongs inside the Add/Edit Memory flow of a specific book.** There must
be no generic Home-screen "upload photo" experience. An earlier attempt that put photo
functionality on the Home screen was rejected.

### 7.4 Edit Memory

Edit reuses the same form/component as Add rather than becoming a separate UX. From
Edit the user can change text, change the date, add photos, and remove photos.
Changing the date immediately changes chronological placement in both the timeline
and the generated album.

UI direction: tapping a memory card opens it directly in the Edit Memory form — no
three-dot menu or intermediate detail view. Delete is its own icon directly on the
card (§7.5), not a menu action. Date editing lives inside Edit Memory, not as a
separate action. Avoid duplicate flows.

### 7.5 Delete

Deletion requires confirmation. Deleting a memory removes the memory metadata, and
its associated photo files should be cleaned up where appropriate.

**Rule:** never delete an underlying photo file while another valid application object
still references it. Even if today one photo belongs to one memory, keep the
separation so future sharing does not become destructive.

Partial-failure cases that need deliberate handling:
- Photo store delete succeeds, Firestore delete fails
- Firestore delete succeeds, photo store delete fails
- Upload succeeds, Firestore save fails

The app should avoid, or later clean up, orphaned files.

### 7.6 Monthly reminders

Around the monthly anniversary of the birth date, send a push notification such as
"Noa is 6 months old! What's new?" Tapping it opens the Add Memory flow for the
correct book. After 12 months, switches to a yearly birthday reminder instead of
continuing monthly (confirmed 2026-09-03 — not indefinite monthly).

Also sends an inactivity nudge per book — if more than 3 weeks pass without a new
memory, a reminder that it's been a while (14-day cooldown between repeat nudges for
the same book, so it doesn't fire daily once past the threshold).

**Built, not yet deployed or confirmed end-to-end (§20).** `functions/notifications.js`
(`sendBookReminders`, a daily `onSchedule` Cloud Function) implements both reminder
types. Client side: `NotificationService` requests permission, registers/refreshes
the FCM token to `users/{uid}.fcmTokens`, and handles tap-to-open (foreground,
background, and cold-start via `getInitialMessage`) navigating to Add Memory for the
book named in the notification's `data.bookId`, using a `navigatorKey` (`lib/
navigation.dart`) added to `MaterialApp` since notification taps have no
`BuildContext` of their own. **Not yet done:** deploying the Cloud Function
(`firebase deploy --only functions` — a deploy is a real-infrastructure action, left
for explicit user confirmation rather than run automatically), and no on-device
confirmation yet that a real notification was received and tapped correctly.

---

## 8. Data model

### 8.1 Memory dates — a central decision

Every memory carries at least two dates:

- **`memoryDate`** — when the remembered event actually happened.
- **`createdAt`** — when the parent entered it into Baby Book.

**Ordering everywhere — timeline and album — is by `memoryDate`.**

If `memoryDate` is not explicitly chosen, it defaults to the creation date.

Example: in August a parent remembers something from June. They add it in August and
set `memoryDate` to June. It must appear in the June position.

`createdAt` must be preserved. `memoryDate` must stay editable. Do not add schema
constraints such as `memoryDate <= first birthday` — the book continues past year one.

### 8.2 A Memory may contain

- text only
- photos only
- text + one photo
- text + multiple photos

All four must feel equally natural.

### 8.3 Photo references

Firestore stores **references and metadata** about photos, never the image bytes.
There is a `PhotoReference` model in the repository — do not revert photo references
to bare strings. Useful metadata includes: storage file ID, thumbnail reference,
uploader/owner, creation info, and possibly MIME type and size.

Use the current repository model as the implementation source of truth.

### 8.4 Conceptual schema

Field names may change during implementation.

```
users/{uid}
  displayName, email, createdAt

books/{bookId}
  childName, birthDate, birthDetails, language, ownerIds, memberIds, createdAt

books/{bookId}/memories/{memoryId}
  memoryDate, text, photoRefs[], createdBy, createdAt, updatedAt, hiddenFromBook

books/{bookId}/exports/{exportId}
  status, createdAt, pdfPath, version
```

Firestore has no migration system. Before real user data exists, decide and document
how memory documents will evolve — for example a `schemaVersion` field.

---

## 9. Architecture

### 9.1 Confirmed

**Flutter** on the client, **Firebase** as the managed backend, cloud-first with a
local cache.

| Component | Responsibility |
|---|---|
| Firebase Authentication | Baby Book account, sign-in, UID |
| Cloud Firestore | Books, memories, text, dates, membership, photo metadata |
| Cloud Messaging | Push notifications for monthly reminders |
| Cloud Functions / Cloud Run | `enhanceMemoryText` (§15) live on Vertex AI — see §10.2 for why it's not on the Developer API's free tier; cleanup, PDF generation, thumbnails still future work |
| Local cache | Fast reads, weak-connection use, save/upload queue |

**Why not store everything only on the phone:** losing or replacing a phone must not
erase a year of memories; two parents need to see the same book; PDF generation is
easier when the source is in the cloud. A local cache still makes the app feel instant.

### 9.2 Three separate identity concerns

Do not merge these:

1. **Baby Book identity** — Firebase Auth / UID.
2. **Book membership** — Firestore authorization and business logic.
3. **Photo storage authorization** — the OAuth grant for whichever photo store is used.

Being signed into Baby Book does not mean photo storage is connected. Disconnecting
photo storage must not delete the Baby Book account.

Google sign-in is a deliberate exception, not a violation of this: it bundles Baby
Book identity and Drive photo-storage authorization into one consent step for UX
simplicity (`AuthRepository.signInWithGoogle`), while still keeping them as separate
concerns underneath — the Drive account is remembered against the signed-in `uid` in
Firestore (`GoogleDriveService.rememberSignedInAccountFor`), not fused into the auth
credential itself. An email/password account can separately link Google later (Home
screen "Link Google Account") to gain photo storage without changing identity.

### 9.3 Photo storage — Cloudflare R2

**Decided (2026-08-30).** Photo bytes will be stored in a Cloudflare R2 bucket
owned by the Baby Book operator, replacing Google Drive. `GoogleDriveService`
remains in place and in use for the current milestone (§21) — this is the target
architecture for a future migration, **not yet implemented**.

**Why not Google Drive (closed).** The PRD originally specified Firebase Cloud
Storage; that was replaced with Google Drive on the premise that photos could live
in each user's own free Drive quota at zero cost to the operator. That premise is
now invalidated: `drive.file` access does not extend to a folder shared by another
user, confirmed by hands-on two-account device testing (Google's own docs and
public developer discussion don't cover this scenario, so documentation research
alone was inconclusive):

- Account A shared its Drive root folder with Account B (`permissions.create`,
  reader role) — confirmed working; the folder and a pre-existing test file were
  visible under Account B's "Shared with me" in the Google Picker for
  desktop/mobile apps (`AuthorizationRequest` + `PICKER_OAUTH_TRIGGER`, Android's
  Play Services Identity API — no Flutter plugin exists for this; it required
  native Kotlin platform-channel code, and has no iOS equivalent at all).
- Account B selected that folder via the Picker (`PICKER_ALLOW_FOLDER_SELECTION`)
  and completed the OAuth consent grant, producing a valid `drive.file`-scoped
  access token.
- That token: succeeded on `drive/v3/about` (HTTP 200 — the token itself is valid
  and correctly authenticated as Account B); failed on `files.get` for the picked
  folder's own id (HTTP 404); failed on `files.get` for a file that existed inside
  that folder *before* the grant (HTTP 404).

Conclusion: selecting a shared folder through the Picker does not grant read
access to it via the Drive API — not to the folder object itself, let alone its
contents. The broader (non-`drive.file`) `drive` scope would fix this but requires
an annual third-party CASA security assessment (~$540/year minimum) — ruled out on
cost for a small app. One variant was identified but not pursued further: sharing
and picking a specific *file* directly, rather than a folder, since `drive.file`'s
own scope description is "files that you open... with an app" and folder-selection
in the Picker may only be intended for choosing a save destination. The team chose
to commit to R2 rather than continue investigating Drive.

**Why R2.** Cost-modeled against real 2026 pricing rather than reasoning from fear
of Firebase Storage specifically (see table below). R2 has unconditional $0 egress,
which matters because this app's usage is egress-heavy — parents repeatedly
browsing photo galleries, not a write-once-read-never pattern. Backblaze B2 is
cheaper on raw storage and was seriously considered, but its free-egress allowance
is capped at 3x monthly storage rather than unconditional; R2 was preferred for the
simpler, harder-to-blow-through cost model. Firebase Storage was reconsidered on
its actual numbers and lost on cost at scale, not on assumption.

| Backend | @1,000 books | @10,000 books | Egress model |
|---|---|---|---|
| Firebase Storage | ~$38/mo | ~$380/mo | $0.026/GB storage + $0.12/GB egress (first 1TB tier) |
| **Cloudflare R2 (chosen)** | ~$15-20/mo | ~$150-200/mo | $0.015/GB storage, **$0 egress** |
| Backblaze B2 | ~$6/mo | ~$60/mo | $0.006/GB storage, free egress up to 3x storage/mo |

(2026 pricing; ~1GB/book/year assumption at 2 photos/memory, ~200 memories/year,
~2MB/photo after compression.)

**Consequence:** this reintroduces a real, use-scaling hosting cost that Drive's
model was specifically chosen to avoid. §10.2's monetization item is now
load-bearing, not a someday-item.

**Target architecture (design only — build during the actual migration):**

- **The client never holds R2 credentials.** A small signing backend (a Cloud
  Function, alongside the existing Firebase project) is the only thing with R2
  write/delete access. It authenticates the caller via their Firebase ID token and
  checks Firestore book membership before issuing anything. This is R2's
  equivalent of "Firestore and storage security rules enforce authorization
  server-side on every read and write" (§12) — R2 has no native per-object rules
  engine, so the signing backend *is* the security boundary.
- **Upload:** client asks the backend for a short-lived presigned PUT URL for a
  known object key, uploads the original and the client-generated thumbnail
  directly to R2, then writes the `PhotoReference` to Firestore. The existing
  upload-then-write-then-rollback-on-failure order in `MemoryService.saveMemory`
  carries over unchanged — only what `PhotoStorageService` talks to changes.
- **Download:** client asks the backend for a short-lived presigned GET URL per
  photo. **No permanent public URLs** (§12, hard rule) — R2 supports a public
  bucket/custom domain, but that option is off the table for this reason alone.
- **Delete:** routed through the backend, never done client-side, for the same
  reason upload and download are signed rather than direct.
- **Object keys** mirror the current Drive folder convention —
  `books/{bookId}/{photoId}-original.{ext}` and
  `books/{bookId}/{photoId}-thumb.jpg` — so authorization checks and cleanup stay
  keyed on `bookId`, the same way `GoogleDriveService` keys on it today via Drive
  `appProperties`.
- **This is also what finally satisfies §11 properly:** access is gated on
  Firestore book membership, not on whose personal cloud account a photo happens
  to live in — the exact problem that made Drive unworkable for a shared book.
- Keep "bring your own storage" as an optional later mode; not required for the
  migration itself.

---

## 10. Open decisions

Nothing in this section should be silently resolved in code. Propose, then record
the decision here.

### 10.1 Photo storage — resolved, see §9.3

Closed 2026-08-30: Cloudflare R2, replacing Google Drive. Decision, evidence, cost
math, and target architecture are recorded in §9.3, not here — this entry is kept
only so existing cross-references to "§10.1" still land somewhere meaningful.
Migration itself is not yet implemented; `GoogleDriveService` remains in use for
the current milestone (§21).

### 10.2 Other open items

- Photo compression policy and maximum photos per memory *(high leverage — affects
  cost, timeline performance, upload reliability, and print quality at once)*
- Thumbnail generation architecture
- Whether co-parent sharing enters the first vertical slice or immediately after
- Member invitation UX and owner transfer
- Behavior when a collaborator disconnects their photo storage
- Behavior when photo files are deleted externally
- Offline upload queue implementation
- iCloud / OneDrive / local-only storage modes
- Home screen layout for one book vs. several
- Whether Generate Book is always available or gets a special CTA near age one —
  partly moot now that Generate/Preview merged into one always-available **Album**
  menu entry (§14), but the "special CTA near age one" idea itself is still open.
- **Print vendor compatibility** — see §14's "Print target" note. Albume.co.il under
  consideration, not committed; needs direct vendor confirmation of whether they even
  accept a submitted PDF before real compatibility work is worth doing.
- **Monetization model** — currently unspecified anywhere. The natural fit is free
  capture, paid PDF export or printed book. Now load-bearing, not just a nice-to-have:
  §9.3's R2 decision gives the operator a real, use-scaling hosting cost that Drive
  didn't have. Album generation itself stayed free/client-side specifically to avoid
  making this more urgent than it already is.
- **AI enhancement backend (§15) — blocking, temporary state.** Target architecture
  per the "users own their own costs" principle (§4) is BYOK: each user supplies
  their own free Gemini API key, client calls Gemini directly, operator pays and
  sees nothing. **Currently impossible for anyone** — verified 2026-08-30 against
  Google's AI Developer Forum (multiple threads, one with a Google staff reply):
  AI Studio now issues only the new `AQ.`-prefix key format, and that format
  currently 401s on `generateContent` with `ACCESS_TOKEN_TYPE_UNSUPPORTED` for
  every caller, Google-acknowledged, no ETA, no workaround — this blocks the
  operator's own free-tier key exactly as much as it would block a user's own key,
  so BYOK isn't buildable right now regardless of UX investment. Also verified: no
  OAuth mechanism lets "sign in with Google" bill a third-party app's AI usage to
  the signed-in user's own account — Google had exactly this (`peruserquota`
  scope) and deprecated it after "unexpected billing" reports. On-device AI
  (Gemini Nano/ML Kit GenAI) was evaluated and rejected as the primary path: its
  Rewriting/Proofreading APIs don't support Hebrew (confirmed against the actual
  API docs — supported languages are English/Japanese/French/German/Italian/
  Spanish/Korean), and device coverage is flagship-only either way. Apple
  Foundation Models (iOS) do support Hebrew and could be a later opportunistic
  addition, but can't be the whole answer since Android has no equivalent.
  **Current stopgap:** `enhanceMemoryText` calls Gemini 3.1 Flash-Lite via Vertex
  AI, authenticated with the Cloud Function's own service-account identity (no
  API key, sidesteps the bug entirely) — operator-paid, cheap (§6 of the AI
  analysis: fractions of a cent per call), explicitly agreed as temporary.
  **Revisit:** switch to real BYOK once Google fixes the Developer API key bug;
  retire the Vertex AI path at that point rather than keeping it as a permanent
  parallel option.
- **Competitive positioning** — Tinybeans, FamilyAlbum, Qeepsake, and Lifecake occupy
  this space. The current differentiators appear to be first-class Hebrew/RTL and the
  no-questionnaire philosophy. State this explicitly.

---

## 11. Sharing between parents

A Baby Book is ultimately a shared family space.

Typical case: Parent A creates the child's book, Parent B joins, both see the same
timeline, both can add memories, both can edit memories, both can add and remove photos.

Each memory stores `createdBy` for basic audit, but the UI should not be cluttered
with "who wrote what" unless it proves useful.

**Do not weaken this product requirement just because photo-store ownership makes it
harder.** Once a photo is part of a shared book, authorized members should be able to
see and manage it appropriately. The technical mechanism is Cloudflare R2 (§9.3):
access gated on Firestore book membership via a signing backend, not on whose
personal cloud account a photo happens to live in — this is precisely why Google
Drive could not satisfy this requirement.

Additional family roles, such as read-only access for grandparents, come later.

---

## 12. Security and privacy

Books contain private family information and children's photos. Security is a product
requirement, not an add-on.

- **Default: books are fully private.**
- Access only for the owner and explicitly invited members.
- Firestore and storage security rules enforce authorization **server-side** on every
  read and write. Never rely on UI hiding alone.
- No permanent public URLs for photos.
- Account deletion must have a defined path for removing all of a user's data, with an
  explicit policy for shared books where one member leaves.
- Before production: Privacy Policy, Terms, and a retention policy.
- Israel's Privacy Protection Law Amendment 13 imposes meaningful obligations. Given
  the subject matter is children's photographs, treat retention and deletion as a real
  design task rather than a checkbox.

---

## 13. Hebrew, English, and RTL

Hebrew is not a later translation exercise. Build layouts RTL-capable from the start.

- UI language: Hebrew or English.
- Book language may eventually be set per book, separately from UI language.
- A Hebrew book needs RTL page direction, text, numbering, and layout.
- Mixed content — Hebrew text with numbers or English — must stay readable and must
  not break layout.
- The final generated Hebrew book must be genuinely RTL, not Hebrew strings in an
  LTR album.
- Dates and typography need explicit attention in both directions.

---

## 14. Album generation and PDF

**Priority moved up 2026-09-03, by explicit user direction, ahead of §21's original
ordering** ("stabilize the vertical slice before... album generation"). Recorded here
rather than silently deviating from that ordering — §21's vertical-slice bar still
stands as the eventual target; this work happened in parallel because the user asked
for it directly, not because the bar was met.

The album is built from saved memories, ordered by `memoryDate`. The system does not
rewrite the story — it finds a good way to present content the parent already created.

### Architecture (decided and built, v1)

- **Client-side rendering, no server involved** — matches the "users own their own
  costs" principle (§4). A prototype (real Hebrew text, real bidi) confirmed the
  Flutter `pdf` package handles RTL correctly; this closes the "PDF rendering
  approach" item that used to be open here in §10.2.
- **One content plan, two renderers.** `AlbumLayoutBuilder` turns a book's memories
  into an ordered, design-agnostic `List<AlbumPage>` (sealed type: cover page, month
  divider, memory page) — no image bytes touched, so computing a page count doesn't
  require downloading a single photo. Two renderers consume that same plan:
  `AlbumPageWidget` (Flutter widgets, for the in-app viewer) and `AlbumPdfRenderer`
  (the `pdf` package, for export). Both read the same `AlbumDesignTheme` values, so a
  design can only be defined once — this is the deliberate answer to "preview must
  match export": neither renderer decides layout on its own, they only paint what the
  shared plan already decided.
- **No persisted album document for v1.** "Generate Album" and "Preview Album" from
  earlier discussion turned out to be the same action — both just compute the plan
  fresh from current memories — so they merged into one **Album** entry in the book's
  options menu (§7.2) rather than staying two. Reopening it after a first generation
  jumps to the last-used design. No editing, hiding, or reordering yet (see "Album
  editor" below — that whole feature is deferred, not built).
- **Timeline grouping by age in months.** Memories are grouped by months-since-birth
  (not calendar month), with a divider page before each new month — carries a
  representative photo from that month when one exists. Matches the monthly-reminder
  convention already used in §7.6.
- **RTL is detected from content, not `Book.language`.** `BookRepository.createBook`
  hardcodes `language: 'en'` always — nothing in the app currently sets a book to
  Hebrew — so trusting that field silently broke RTL for every real Hebrew book
  (found via on-device testing, not by inspection). `AlbumLayoutBuilder.detectIsRtl`
  instead checks the child's name and memory text for Hebrew script and treats the
  whole album as RTL if any is found — a real per-book language field/setting is
  still open (see Album Settings below).
- **Three designs, one palette.** `AlbumDesign`: Soft Pastel (plain), Soft Pastel —
  Minimal (small corner icon accents), Soft Pastel — Framed (scalloped border, accent
  photo frame, name badge). All three share one `AlbumDesignTheme` and differ only in
  `coverDecoration` — decoration is scoped to the cover page only for now; extending
  it to memory/divider pages is a later step. Icons are Lucide (ISC license,
  `assets/icons/`); the Hebrew font is Noto Sans Hebrew (SIL OFL, `assets/fonts/`) —
  both real, redistributable, licensed assets, not placeholders.
- **Photos render at their true aspect ratio** (from `PhotoReference.width`/`height`,
  already captured at upload time), not cropped to a fixed box — fixed the original
  "photos are cut" bug for single-photo and cover pages. Multi-photo grid pages still
  square-crop each photo by design choice (a masonry-style non-cropping grid is
  requested future work, not yet built).
- **Thumbnail resolution only for v1** — good enough to prove the renderer out; a
  print-resolution asset choice for actual export/printing is deferred (photo storage
  is also mid-migration, §9.3, so this is deliberately not solved twice).

Layout must support (unchanged goal, only single-memory-per-page pages exist so far):

- Text-only memories — integrated naturally between pages, not necessarily a full page.
- Photo-only memories — may get a date caption only, or appear in a collage.
- Text + one photo.
- Text + multiple photos.
- Several short memories from the same period on one page — **not yet built**; v1's
  `AlbumLayoutBuilder` always produces one memory per page (the page model already
  supports a memory list per page for when this is built).
- Long text — choose a suitable layout, split safely, or offer to shorten. Never
  shorten significantly without approval. **Not yet built** — long text currently just
  wraps.

### Print target — open, blocking real compatibility work

User is considering **Albume.co.il** ("Gananot"/yearbook product line) as a print
vendor, explicitly not locked in ("could change in the future"). Investigated
2026-09-03: their public product page gives no evidence of accepting a submitted
PDF — every signal (`editor.albume.co.il`, "design online in our editor, no download
needed") points to designing inside their own proprietary web editor instead. Their
general hardcover book line is A4 portrait, up to 140 pages, but no bleed/margin/DPI
numbers are public. **Needs direct confirmation with the vendor** before investing
further in "compatibility" — if they don't accept a PDF upload, matching their trim
size is the most "compatible" a generated PDF can realistically be.

### Album editor — deferred, not built

Originally scoped for v1, explicitly deferred so a simpler live-preview baseline could
ship first:

- Edit memory text
- Add / remove / replace photos
- Change a date and reflow the book
- Hide a memory from the album without deleting it from the timeline (note:
  `Memory.hiddenFromBook` already exists and is already respected by
  `AlbumLayoutBuilder` — only the UI to toggle it from the album view is missing)
- Choose between layouts where simple to implement
- Regenerate / reflow after a significant change

The PDF must be consistent between preview and final output, including Hebrew and
RTL — see "one content plan, two renderers" above for how v1 enforces this
structurally rather than by convention.

### Menu stubs — visible, not yet built

The book's options menu (§7.2) also has **Album Settings**, **Printing Guide**, and
**Share Album**, each currently an honest "coming soon" — shown so the eventual menu
shape is visible, not because the features exist. Share Album will eventually route to
the co-parent invite flow (§11), once that itself is built.

---

## 15. The role of AI

A rules-based engine with light AI assistance is sufficient for MVP.

**Acceptable:** choosing page layout, photo sizing, fitting text, grouping nearby
memories, page breaks, visual balance.

**Not acceptable by default:** inventing emotional captions, inventing milestones,
rewriting the parent's story, changing facts or meaning, adding a significant
"emotional" heading without an explicit user action, or turning simple memories into
AI-generated narrative.

If text rewriting is ever added, it must be explicit and opt-in.

**Implemented (§20 has current status):** an "Enhance text" button in Add/Edit
Memory opens a single persistent "AI Editor" panel (redesigned from an initial
version that generated 3 variants up front — reworked to match a UI concept
the user provided). **Translate / Style / Fix** are three top buttons that
switch which single suggestion is shown, without ever closing the panel;
picking "Style" reveals a second row of style chips (currently Short / Warm /
Playful, deliberately easy to extend — see `STYLE_INSTRUCTIONS` in
`functions/index.js`). Each button/chip tap calls `functions/enhanceMemoryText`
(Gemini 3.1 Flash-Lite via Vertex AI — see §10.2 for why not the Developer
API) for that one action and shows the result inline in the same panel. An
explicit **Apply** button is the only thing that copies the result into the
text field — closing the panel any other way (X, back gesture, tap outside)
leaves the original untouched, satisfying "never applied automatically"
without needing a dedicated "keep my original" control.

The prompt (`buildSystemInstruction()` in `functions/index.js`) is the actual
enforcement point for the "not acceptable" list above, built per-mode rather
than as one static string — "Translate" is the one case that must explicitly
override the "never translate" rule the other two modes need. Shared hard
rules across all modes: never fabricate/assume beyond the input, never drop a
stated fact, never touch names/numbers/dates, and — since a first pass read as
noticeably AI-generated — an explicit list of banned tells (cliché phrases,
stacked adjectives, unearned exclamation points, unnaturally symmetrical
sentences). `temperature: 0.5` — deliberately conservative, since a fabricated
detail is a spec violation, not a quality nitpick. Optional `childGender`
(§7.1) is passed as a separate grammar-only context line the model is
instructed never to otherwise reference, for Hebrew agreement.

---

## 16. Non-functional requirements

- Saving a text memory must feel instant. Photo uploads may continue in the background
  with a clear indicator.
- The app must survive weak connectivity without losing entered text or selected photos.
- **Never report Save success before the memory is durable.**
- A timeline spanning years must stay fast via pagination and lazy loading.
- Every mutating or deleting operation should be as idempotent as possible and handle
  retries without creating duplicates.
- Avoid orphaned photo files.
- Do not destructively alter original photos.
- Users may accumulate thousands of images. Long term this needs thumbnails, caching,
  lazy loading, pagination, and compressed previews.

---

## 17. Success metrics

Metrics currently have no targets. Add numeric goals or they will not drive decisions.

| Metric | Definition | Target |
|---|---|---|
| Time to first memory | New user creates a book and saves a first memory | *TBD* |
| Memory capture rate | Active users adding memories over months, not just at signup | *TBD* |
| Book generation rate | Share of users who generate a preview after accumulating content | *TBD* |
| Export completion | Share of users who reach a final PDF | *TBD* |
| Retention | Monthly return around reminders and events | *TBD* |

Analytics and crash reporting are not yet planned. Add them before launch.

---

## 18. Roadmap (post-MVP)

- Video and audio
- Automatic import from Google Photos / Apple Photos by date
- Optional, opt-in AI suggestions for titles or phrasing
- Additional themes and book designs
- Printing and shipping through the app — Albume.co.il under consideration as a
  vendor, not committed; see §14's "Print target" note for the open compatibility
  question
- Timeline into later childhood with chapters or years
- Read-only sharing with grandparents and extended family
- iCloud / OneDrive / local-only photo storage modes

---

## 19. Continuing past the first year

At the end of the first year the user can choose **Continue Book**. No separate product
is needed — the same book keeps accepting memories and dates. Division into years or
chapters ("Year 2", "First kindergarten", "Trips") can come later and is not required
for MVP.

---

## 20. Current implementation status

Already built:

- Flutter app created
- Firebase project connected
- Firebase Auth work, including Google sign-in with silent account persistence
  (§9.2) and Drive access granted in the same consent step
- Firestore-based Book repository
- Home screen listing books, showing each book's cover photo (§7.1/§7.2)
- Book creation/edit flow, including the optional birth-info questions and
  birth photo gallery (§7.1)
- Book screen, with the cover photo shown at the top of the album
- Memory model and Memory repository
- Add/Edit Memory form work, tap-to-edit + a delete icon on the card (§7.4)
- Image picker integration
- Google Drive service and Drive photo upload
- Drive photo references connected to memories
- `firebase_storage` dependency removed
- AI Editor (§15) — `functions/enhanceMemoryText`, Gemini 3.1 Flash-Lite via
  Vertex AI (§10.2). Confirmed working end-to-end on-device across two rounds
  of user feedback: the original "3 variants at once" design became the
  current single-panel Translate/Style/Fix redesign, and the prompt itself
  was hardened twice (anti-fabrication hard rules, per-style length ceilings,
  Hebrew-gender context via `childGender`).
- Ideas bank (§7.2): ~100 age-tagged prompts, 14 categories, English + Hebrew,
  per-book "already captured" soft checklist.
- Book screen options menu (§7.2): consolidated Ideas/Album/Album Settings/Printing
  Guide/Share Album/Edit Book Info/Rename Book/Delete Book into one ⋮ menu, moved off
  the Home screen's per-card menu.
- Album generation v1 (§14): client-side, no server cost, 3 designs, month-based
  timeline grouping, in-app page-by-page viewer, PDF export via the share sheet
  (`printing` package). Non-editable; see §14 for what's still deferred.
- Notifications client + backend written (§7.6) — Cloud Function not yet deployed,
  not yet confirmed end-to-end on a real device.
- Google sign-in "account picker every launch" bug — root-caused and fixed in
  `GoogleDriveService._connectSlow` (a destructive `signOut()`/`clearCredentialState()`
  call in the silent-restore fallback was wiping the exact state needed for the next
  silent restore). Not yet confirmed on-device; further sign-in UX work paused at the
  user's request pending confirmation this is even the direction wanted.

Files seen during development (verify against Git for exact current names):

```
lib/features/home/home_screen.dart
lib/features/books/book_screen.dart
lib/features/books/book_form_screen.dart
lib/features/memories/...
lib/features/albums/album_page_widget.dart
lib/features/albums/album_generate_sheet.dart
lib/features/albums/album_viewer_screen.dart
lib/data/repositories/memory_repository.dart
lib/data/repositories/book_repository.dart
lib/data/services/book_service.dart
lib/models/memory.dart
lib/models/book.dart
lib/models/album_page.dart
lib/models/album_design.dart
lib/models/album_design_theme.dart
lib/services/google_drive_service.dart
lib/services/ai_text_enhancement_service.dart
lib/services/album_layout_builder.dart
lib/services/album_pdf_renderer.dart
lib/services/notification_service.dart
lib/data/idea_prompts.dart
lib/models/idea_prompt.dart
lib/features/books/ideas_screen.dart
lib/navigation.dart
functions/index.js
functions/notifications.js
```

### Known unfinished work

- **Latest AI Editor panel redesign and Ideas screen tap-animation change are
  built, installed, not yet confirmed on-device.** No Cloud Function redeploy
  needed for this round (only client-side changes).
- **Sharing between parents (§11) has no invite/add-member UI at all.**
  `ownerIds` is created as a single-element array at book creation with no
  code path to add a second person. The Firestore rules already correctly
  support multi-owner books (array-membership check, not "must equal
  creator") — only the actual invite UI is missing. Untested with a real
  second device.
- **Google sign-in `PROVIDER_ALREADY_LINKED` — fix applied, not yet confirmed.**
  An account already linked to Google via an earlier session (either this one's
  own testing, or a real prior link) would fail on a fresh `signInWithCredential`
  even after clearing local app data. Root cause: `signInInteractively()` called
  `_googleSignIn.authenticate()` without first calling `.signOut()` — the newer
  Credential-Manager-backed `authenticate()` can silently hand back a cached
  session/token instead of a fresh OAuth exchange, and a reused token already
  consumed by an earlier `linkWithCredential` call gets rejected by Firebase's
  backend as already used. Fixed by adding `_googleSignIn.signOut()` before
  `authenticate()` (the same pattern `changeAccount()` already used) — deployed,
  awaiting on-device confirmation.
- **Push notifications (§7.6) built, not deployed or confirmed.** See §7.6 for what's
  actually done vs. missing.
- **Album generation (§14) follow-ups**, roughly in the order they'd matter: deploy
  is n/a (client-only) but photo resolution is thumbnail-only (print-quality export
  needs real resolution), decoration is cover-page-only, grid photos still
  square-crop, the print vendor question is unresolved, and Album Settings/Printing
  Guide/Share Album are stubs. None of this blocks using the album feature today —
  it's real, tested, on-device — these are the known gaps, not defects.

---

## 21. Current milestone — the vertical slice

Stabilize this end-to-end before moving to AI, reminders, album generation, printing,
or themes:

1. Open app
2. Authenticate
3. Create / open a child's book
4. Add a memory
5. Add text and/or multiple photos
6. Save
7. Close and restart the app
8. Reopen
9. See the same memory in the correct chronological position
10. Open it and see its photos
11. Edit it
12. Delete it safely

Immediately after that: co-parent collaboration, or the Hebrew/RTL foundation.

**Note (2026-09-03):** reminders (§7.6) and album generation v1 (§14) were built
ahead of this ordering, at the user's explicit direction in-session — not because
this checklist was confirmed complete. Recorded here rather than silently reordered;
this checklist is still the bar for calling the core loop itself stable.

---

## 22. Development environment and workflow

Windows, VS Code, PowerShell. Typical project path `C:\Baby_App\App_Dev\my_app`.
A physical Nothing phone appeared as device `A001` for `flutter run`.

Flutter was installed from a recent master-channel build — roughly Flutter
`3.47.0-1.0.pre` and Dart `3.14.0 dev` at one point. **If unexpected package or plugin
compatibility problems appear, check the Flutter channel and version before assuming
application code is wrong.**

Git pushes from the work computer failed while connected to the corporate VPN.
Disconnecting the VPN resolved it. Git or network failures from that environment may
have nothing to do with repository configuration.

### Working style

- Incremental. Avoid large refactors without clear value.
- For meaningful changes: keep scope understandable, explain which files change, run
  `flutter analyze`, fix analyzer issues before moving on, test the real flow on device
  where practical, and commit stable checkpoints.
- The user is actively learning and wants to understand *why* architectural decisions
  are made. Do not dump large unexplained code into the project.
- **Do not invent product requirements.** If something is undecided, mark it open in
  §10 rather than silently choosing a direction.

---

## 23. UX language — hide the infrastructure

Users are creating memories, not managing cloud services.

Avoid in normal UX: "Upload to Google Drive", "Firestore saved", "Drive File ID",
"Connect storage backend".

Use: Add photo, Save memory, Edit, Delete, Book, Photos.

Storage authorization screens may obviously name the provider when required.

---

## 24. Decisions already closed

| Topic | Decision |
|---|---|
| Sign-in method | Email/Password and Google (linkable either direction); Google grants Drive access in the same consent step. Apple not yet planned. |
| Capture method | Free-form. Never a mandatory questionnaire. |
| Memory contents | Text and/or photos, plus a date. |
| Ordering | Chronological by memory date, editable. |
| Writing prompts | Optional Ideas/info button. |
| AI | Behind the scenes, assistive only. |
| Output | An editable book, not a fixed result. |
| After age one | The same book continues. |
| Hebrew | Core feature, including RTL in the book itself. |
| Data storage | Cloud-first with local cache. |
| Photo storage | Cloudflare R2 — see §9.3. Not yet implemented. |
| Album rendering | Client-side, `pdf` package, no server cost — see §14. |
| Album v1 scope | Non-editable; Generate/Preview merged into one entry — see §14. |

---

## 25. What Baby Book must not become

- A mandatory milestone questionnaire
- A social network
- A public family photo platform
- An AI storytelling chatbot
- A complicated photo-management application
- A project-management-style timeline
- A mandatory daily journal

The core appeal is low-friction memory capture.
