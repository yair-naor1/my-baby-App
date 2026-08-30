# Baby Book — project instructions

## What this project is

A Flutter + Firebase app that lets parents capture memories of a child's first year
and later turn them into an editable, exportable photo book. Hebrew and RTL are
first-class requirements.

**Read `docs/PRODUCT_SPEC.md` before any product or architecture decision.**
It is the single source of truth. If it conflicts with older documents, it wins.
If it conflicts with the code, inspect the code first, then update the spec.

## The one-line test for any decision

> Does this make it easier and safer for a parent to capture a memory now and still
> have it years later?

## Hard rules

- **Do not invent product requirements.** If something is undecided, say so and add it
  to §10 of the spec. Do not silently choose a major product direction.
- **Do not reintroduce Firebase Storage** without an explicit decision — see §9.3/§10.1.
- **Order by `memoryDate`, never `createdAt`.** Both fields must be preserved.
- **Never report Save success before the memory is durable.**
- **Do not delete a photo file while another object still references it.**
- **Add Photos lives inside Add/Edit Memory**, never on the Home screen.
- **Never expose infrastructure in UX copy** — no "Upload to Google Drive", no
  "Drive File ID". Just: Add photo, Save memory, Edit, Delete, Book, Photos.
- Technical documentation is written in **English**, even though the app is bilingual.

## Working style

- Incremental changes. No large refactors without clear value.
- Before finishing any change: run `flutter analyze` and fix the issues.
- State which files you are changing and why, before changing them.
- Explain architectural reasoning — I am learning this codebase as we build it.
- Commit stable checkpoints. Small, described commits.

## Environment notes

- Windows / VS Code / PowerShell. Project at `C:\Baby_App\App_Dev\my_app`.
- Flutter is on a recent **master channel** build (~3.47.0-1.0.pre, Dart 3.14 dev).
  If a plugin behaves strangely, check the channel before blaming app code.
- Test device: Nothing phone, appears as `A001`.
- Git push fails on the corporate VPN. Disconnect the VPN — it is not a repo problem.

## Current milestone

Stabilize the vertical slice (spec §21) before touching AI, reminders, album
generation, or themes:

Open app → authenticate → create/open a book → add a memory with text and multiple
photos → save → restart → memory still there in the right chronological position →
photos visible → edit → delete safely.

## Immediate known issue

Google account persistence. The user must not be prompted to pick a Google account on
every launch. Silent restoration is partly implemented; there was an analyzer error
around `.email` on a nullable restored account. Inspect the current state of
`GoogleDriveService` before rewriting anything.
