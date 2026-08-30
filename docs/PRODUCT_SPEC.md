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
and **birth date**. Optional fields may include birth place, birth time, weight/height
at birth, the birth story, and a cover photo.

Do not hard-code the app around exactly one child or one book. The Home screen is a
list of books, normally one per child.

### 7.2 Book screen (the timeline)

This is the main day-to-day screen. The child/book appears at the top, the memory
list in the middle, and a prominent, always-reachable **Add** button.

- Chronological list of all memories.
- Each item shows: memory date, a short text preview if there is text, and small
  photo previews if there are photos.
- Tapping an item opens the full memory view with Edit / Delete available.
- Add is reachable without passing through a questionnaire or wizard.

**Performance rule:** a timeline card shows at most **2–3 small, low-resolution
previews** even when the memory has many photos. The full memory view shows all
photos. Never render the timeline by downloading full-resolution images.

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
| Ideas (i) | Optional list of prompts. Does not change the main Add screen. |

At least some meaningful content (text or a photo) must exist before saving.

**Add Photos belongs inside the Add/Edit Memory flow of a specific book.** There must
be no generic Home-screen "upload photo" experience. An earlier attempt that put photo
functionality on the Home screen was rejected.

### 7.4 Edit Memory

Edit reuses the same form/component as Add rather than becoming a separate UX. From
Edit the user can change text, change the date, add photos, and remove photos.
Changing the date immediately changes chronological placement in both the timeline
and the generated album.

UI direction: a three-dot menu on a memory with **Edit** and **Delete**. Date editing
lives inside Edit Memory, not as a separate menu action. Avoid duplicate flows.

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
correct book. Not an immediate development priority.

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
| Cloud Functions / Cloud Run | Future backend work: cleanup, PDF generation, thumbnails |
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

### 9.3 Photo storage — UNRESOLVED, see §10.1

The PRD originally specified Firebase Cloud Storage. That was later replaced with
**Google Drive**, and `firebase_storage` was removed from the project. A
`GoogleDriveService` exists in the repository.

The motivation was cost: a baby album can hold a large number of high-resolution
images, and the operator should not pay to host every user's personal photo library.
The intended model was *"your photos live in your own cloud storage; Baby Book
organizes them."*

**This decision is now reopened.** See §10.1 before writing further Drive code.

If Drive remains in use: request the minimum reasonable permission scope, prefer
operating only on files the app created, and never scan unrelated Drive content.

---

## 10. Open decisions

Nothing in this section should be silently resolved in code. Propose, then record
the decision here.

### 10.1 Photo storage — blocking

Google Drive as the photo store may be incompatible with the shared-book requirement
(§11). The `drive.file` scope grants an app access only to files it created for that
specific user, so a second parent's app instance would not be able to read the first
parent's photo. Broader scopes are "restricted" and require an annual third-party
security assessment.

**Action:** verify this against Google's current OAuth scope and API Services User
Data Policy documentation before further Drive work. If confirmed, evaluate
object storage with low or zero egress cost (for example Cloudflare R2 or Backblaze B2)
combined with aggressive compression, and keep "bring your own storage" as an optional
later mode.

Run the actual cost math with real assumptions rather than reasoning from fear of
Firebase Storage pricing specifically.

### 10.2 Other open items

- Photo compression policy and maximum photos per memory *(high leverage — affects
  cost, timeline performance, upload reliability, and print quality at once)*
- Thumbnail generation architecture
- Sign-in method: Email/Password, Google, Apple, or a combination
- Whether co-parent sharing enters the first vertical slice or immediately after
- Member invitation UX and owner transfer
- Behavior when a collaborator disconnects their photo storage
- Behavior when photo files are deleted externally
- Offline upload queue implementation
- iCloud / OneDrive / local-only storage modes
- Generated book editor UX in detail
- Home screen layout for one book vs. several
- Whether Generate Book is always available or gets a special CTA near age one
- **Monetization model** — currently unspecified anywhere. The natural fit is free
  capture, paid PDF export or printed book. This decision materially affects §10.1.
- **PDF rendering approach** — client-side vs. server-side. Flutter's `pdf` package has
  weak RTL shaping and bidi handling. Prototype a Hebrew page early, before building
  an editor on top of an approach that cannot render it.
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
see and manage it appropriately. The technical mechanism is open (§10.1).

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

**Not the current priority. Do not start this before memory capture and storage are
rock solid.**

The album is built from saved memories, ordered by `memoryDate`. The system does not
rewrite the story — it finds a good way to present content the parent already created.

Layout must support:

- Text-only memories — integrated naturally between pages, not necessarily a full page.
- Photo-only memories — may get a date caption only, or appear in a collage.
- Text + one photo.
- Text + multiple photos.
- Several short memories from the same period on one page.
- Long text — choose a suitable layout, split safely, or offer to shorten. Never
  shorten significantly without approval.

### Album editor

After Generate Book the user sees a preview and can edit before export:

- Edit memory text
- Add / remove / replace photos
- Change a date and reflow the book
- Hide a memory from the album without deleting it from the timeline
- Choose between layouts where simple to implement
- Regenerate / reflow after a significant change

The PDF must be consistent between preview and final output, including Hebrew and RTL.

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
- Printing and shipping through the app
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
- Firebase Auth work
- Firestore-based Book repository
- Home screen listing books
- Book creation flow
- Book screen
- Memory model and Memory repository
- Add/Edit Memory form work
- Image picker integration
- Google Drive service and Drive photo upload
- Drive photo references connected to memories
- `firebase_storage` dependency removed

Files seen during development (verify against Git for exact current names):

```
lib/features/home/home_screen.dart
lib/features/books/book_screen.dart
lib/features/memories/...
lib/data/repositories/memory_repository.dart
lib/models/memory.dart
lib/services/google_drive_service.dart
```

### Known unfinished work

Google account persistence and silent restoration. The user must not be asked to pick
a Google account on every app launch or every photo upload — the service should restore
the previous account silently and only prompt when authorization genuinely cannot be
recovered. An analyzer error existed around accessing `.email` on a nullable restored
account. Inspect the current Git state before writing a new implementation.

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
| Capture method | Free-form. Never a mandatory questionnaire. |
| Memory contents | Text and/or photos, plus a date. |
| Ordering | Chronological by memory date, editable. |
| Writing prompts | Optional Ideas/info button. |
| AI | Behind the scenes, assistive only. |
| Output | An editable book, not a fixed result. |
| After age one | The same book continues. |
| Hebrew | Core feature, including RTL in the book itself. |
| Data storage | Cloud-first with local cache. |
| Photo storage | **Reopened — see §10.1.** |

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
