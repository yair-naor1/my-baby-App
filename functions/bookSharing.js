const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// PRODUCT_SPEC.md §11: co-parent sharing. Firestore rules can't let a
// brand-new joiner add themselves to a book's ownerIds — `allow update`
// requires the caller to *already* be an owner, a chicken-and-egg security
// rules alone can't resolve. This is the same shape as the R2 signing
// backend (functions/r2Storage.js): a Cloud Function is the boundary,
// checking authorization itself and writing via the Admin SDK, which
// bypasses rules once that check has passed.
//
// The "invite code" is just the book's own id — an unguessable ~20-char
// Firestore auto-id, the same "anyone with this can join" model plenty of
// apps use for share links. No expiry or revocation yet (see spec §11) —
// deliberately flagged there as a known v1 gap, not silently solved.
exports.joinBook = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const uid = request.auth.uid;
  const bookId = (request.data && request.data.bookId || "").toString().trim();

  if (!bookId) {
    throw new HttpsError("invalid-argument", "A code is required.");
  }

  const bookRef = admin.firestore().collection("books").doc(bookId);
  const bookDoc = await bookRef.get();

  if (!bookDoc.exists) {
    throw new HttpsError("not-found", "That code doesn't match any book.");
  }

  const data = bookDoc.data();
  const ownerIds = data.ownerIds || [];

  // Re-entering a code you already used isn't an error — idempotent.
  if (!ownerIds.includes(uid)) {
    await bookRef.update({
      ownerIds: admin.firestore.FieldValue.arrayUnion(uid),
    });
  }

  return {childName: data.childName};
});
