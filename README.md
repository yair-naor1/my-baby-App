Baby Book

A mobile app for parents to capture memories from their child's first year — and beyond — and turn them into a beautiful, editable photo album.

Guiding principle: the parent creates the memories; the app helps keep them and present them well.

What it does
Capture in seconds — open the child's book, tap Add, write text and/or attach photos, save. No forms, categories or wizards.
Chronological timeline — memories are ordered by when they happened (memoryDate), not when they were typed, so past moments can be added later.
Multiple books — one book per child, under one account.
Shared with a partner — both parents can add and edit the same book.
Monthly reminders — e.g. "Noa is 6 months old! What's new?" opens straight into Add.
Album generation — builds a chronological, print-ready album from saved memories, editable before export to PDF.
Hebrew & English — full RTL support in the UI and in the album itself.
Continue past year one — the same book keeps growing into a childhood timeline.
AI principles

AI is a helper, not the core experience:

It may help with layout and presentation (page balance, photo placement, text fit).
It must never invent facts, milestones or meaningful captions, or change the meaning of what the parent wrote.
Tech stack
Layer	Technology
App	Flutter
Auth	Firebase Authentication
Data	Cloud Firestore (with local offline cache)
Backend logic	Cloud Functions (incl. Gemini for optional text enhancement)
Photo storage	Object storage (provider under evaluation)
Notifications	Firebase Cloud Messaging
Album rendering	Template-based layout engine → headless Chromium → PDF
Data model (simplified)
users/{uid}
books/{bookId}                      childName, birthDate, language, ownerIds
books/{bookId}/memories/{memoryId}  memoryDate, text, photoRefs[], createdBy, hiddenFromBook
books/{bookId}/exports/{exportId}   status, pdfPath, version
Privacy & security
Books are private by default — access only for the owner and explicitly invited members.
Access is enforced server-side via Firestore and Storage security rules.
No permanent public URLs for photos.
Getting started
Install Flutter.
Clone the repo and run flutter pub get.
Add your Firebase config (flutterfire configure, or place google-services.json / GoogleService-Info.plist in the platform folders). Config files are not committed.
Run flutter run.
Docs

The full product specification lives in docs/PRODUCT_SPEC.md.

Roadmap
Direct print ordering (local print lab first, international POD API later)
Video and audio memories
Import from Google Photos / Apple Photos
Read-only sharing with grandparents
Additional album themes
