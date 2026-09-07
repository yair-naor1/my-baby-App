const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {randomUUID} = require("node:crypto");
const admin = require("firebase-admin");
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require("@aws-sdk/client-s3");
const {getSignedUrl} = require("@aws-sdk/s3-request-presigner");

// PRODUCT_SPEC.md §9.3: the client never holds R2 credentials — this file is
// the only thing with R2 access, gated on the same Firestore book-membership
// check firestore.rules' isBookMember() already enforces for Firestore itself.
// R2 has no native per-object rules engine, so this signing backend *is* the
// security boundary for photo storage.

const R2_ACCOUNT_ID = defineSecret("R2_ACCOUNT_ID");
const R2_ACCESS_KEY_ID = defineSecret("R2_ACCESS_KEY_ID");
const R2_SECRET_ACCESS_KEY = defineSecret("R2_SECRET_ACCESS_KEY");
const R2_BUCKET_NAME = defineSecret("R2_BUCKET_NAME");

const SECRETS = [
  R2_ACCOUNT_ID,
  R2_ACCESS_KEY_ID,
  R2_SECRET_ACCESS_KEY,
  R2_BUCKET_NAME,
];

const UPLOAD_URL_TTL_SECONDS = 5 * 60;
const DOWNLOAD_URL_TTL_SECONDS = 10 * 60;

// Deliberately small — only real photo formats the client ever picks/creates.
// Rejects anything else rather than trusting a client-supplied extension.
const ALLOWED_EXTENSIONS = new Set([
  "jpg",
  "jpeg",
  "png",
  "heic",
  "heif",
  "webp",
]);

// Object keys mirror the Drive folder convention this replaces (spec §9.3),
// so authorization and cleanup stay keyed on bookId either way.
const BOOK_KEY_PATTERN = /^books\/([^/]+)\/[^/]+$/;

let cachedClient = null;

// Strips whitespace AND invisible Unicode formatting characters (zero-width
// spaces/joiners, bidi/RTL control marks, BOM) from secret values. A stray
// character from copy-pasting into `firebase functions:secrets:set` is an
// easy mistake to make — plain .trim() alone didn't catch one here, which
// pointed at an invisible mark rather than an ordinary trailing space —
// and it produces confusing signature/credential-length errors from R2
// rather than an obvious "bad secret" error, so guard against it here once
// instead of relying on every secret always being pasted perfectly clean.
// Built from explicit code points, not literal characters, so the source
// file never contains an actual invisible character itself.
const INVISIBLE_CODE_POINTS = [
  0x200b, 0x200c, 0x200d, // zero-width space / non-joiner / joiner
  0x200e, 0x200f, // LTR / RTL marks
  0x202a, 0x202b, 0x202c, 0x202d, 0x202e, // bidi embedding/override controls
  0x2060, // word joiner
  0xfeff, // BOM / zero-width no-break space
];
const INVISIBLE_CHARS_PATTERN = new RegExp(
    `[\\s${INVISIBLE_CODE_POINTS.map((cp) => `\\u${cp.toString(16).padStart(4, "0")}`).join("")}]`,
    "g",
);

function secretValue(param) {
  return param.value().replace(INVISIBLE_CHARS_PATTERN, "");
}

function getS3Client() {
  if (cachedClient) return cachedClient;

  cachedClient = new S3Client({
    region: "auto",
    endpoint: `https://${secretValue(R2_ACCOUNT_ID)}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: secretValue(R2_ACCESS_KEY_ID),
      secretAccessKey: secretValue(R2_SECRET_ACCESS_KEY),
    },
  });

  return cachedClient;
}

/**
 * Mirrors firestore.rules' isBookMember(bookId): the caller's uid must be in
 * books/{bookId}.ownerIds. Throws HttpsError on any failure so callers never
 * need to distinguish "not found" from "not a member" — both are opaque.
 *
 * [allowPending] permits a not-yet-existing book document to pass. Only ever
 * pass true from getPhotoUploadUrls: BookService.saveBookInfo reserves the
 * bookId, uploads birth photos, *then* creates the Firestore book doc (same
 * upload-before-write ordering MemoryService uses — see PRODUCT_SPEC.md
 * §9.3/§7.1) — for a brand-new book, the doc genuinely doesn't exist yet at
 * upload time. Safe to allow: bookId is an unguessable Firestore auto-id, and
 * Firestore's own security rules still require request.auth.uid in
 * ownerIds at the actual doc-create step, so nothing becomes downloadable
 * (getPhotoDownloadUrl/deletePhotos never pass allowPending) until the real
 * book — with real membership — exists.
 */
async function assertBookMember(uid, bookId, {allowPending = false} = {}) {
  const bookDoc = await admin.firestore().collection("books").doc(bookId).get();

  if (!bookDoc.exists) {
    if (allowPending) return;
    throw new HttpsError("not-found", "Book not found.");
  }

  const ownerIds = bookDoc.data().ownerIds || [];

  if (!ownerIds.includes(uid)) {
    throw new HttpsError(
        "permission-denied",
        "Not a member of this book.",
    );
  }
}

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  return request.auth.uid;
}

function bookIdFromKey(key) {
  const match = typeof key === "string" && key.match(BOOK_KEY_PATTERN);

  if (!match) {
    throw new HttpsError("invalid-argument", "Malformed photo key.");
  }

  return match[1];
}

exports.getPhotoUploadUrls = onCall(
    {region: "us-central1", secrets: SECRETS},
    async (request) => {
      const uid = requireAuth(request);

      const bookId = request.data && request.data.bookId;
      const extension = (request.data && request.data.extension || "")
          .toString()
          .toLowerCase()
          .replace(/^\./, "");

      if (!bookId || typeof bookId !== "string") {
        throw new HttpsError("invalid-argument", "bookId is required.");
      }

      if (!ALLOWED_EXTENSIONS.has(extension)) {
        throw new HttpsError(
            "invalid-argument",
            `extension must be one of: ${[...ALLOWED_EXTENSIONS].join(", ")}`,
        );
      }

      await assertBookMember(uid, bookId, {allowPending: true});

      const photoId = randomUUID();
      const originalKey = `books/${bookId}/${photoId}-original.${extension}`;
      const thumbKey = `books/${bookId}/${photoId}-thumb.jpg`;

      const client = getS3Client();
      const bucket = secretValue(R2_BUCKET_NAME);

      // Content-Type is deliberately left off the signed command so the
      // client can PUT with any Content-Type header without a signature
      // mismatch — this backend doesn't need to police MIME type on upload,
      // only the object key/path.
      const [originalUploadUrl, thumbUploadUrl] = await Promise.all([
        getSignedUrl(
            client,
            new PutObjectCommand({Bucket: bucket, Key: originalKey}),
            {expiresIn: UPLOAD_URL_TTL_SECONDS},
        ),
        getSignedUrl(
            client,
            new PutObjectCommand({Bucket: bucket, Key: thumbKey}),
            {expiresIn: UPLOAD_URL_TTL_SECONDS},
        ),
      ]);

      return {originalKey, thumbKey, originalUploadUrl, thumbUploadUrl};
    },
);

exports.getPhotoDownloadUrl = onCall(
    {region: "us-central1", secrets: SECRETS},
    async (request) => {
      const uid = requireAuth(request);

      const key = request.data && request.data.key;
      const bookId = bookIdFromKey(key);

      await assertBookMember(uid, bookId);

      const client = getS3Client();
      const bucket = secretValue(R2_BUCKET_NAME);

      const downloadUrl = await getSignedUrl(
          client,
          new GetObjectCommand({Bucket: bucket, Key: key}),
          {expiresIn: DOWNLOAD_URL_TTL_SECONDS},
      );

      return {downloadUrl};
    },
);

exports.deletePhotos = onCall(
    {region: "us-central1", secrets: SECRETS},
    async (request) => {
      const uid = requireAuth(request);

      const keys = request.data && request.data.keys;

      if (!Array.isArray(keys) || keys.length === 0) {
        throw new HttpsError("invalid-argument", "keys must be a non-empty array.");
      }

      // Group by bookId so a batch spanning several photos in the same book
      // only checks membership once per book, not once per key.
      const keysByBookId = new Map();

      for (const key of keys) {
        const bookId = bookIdFromKey(key);
        const list = keysByBookId.get(bookId) || [];
        list.push(key);
        keysByBookId.set(bookId, list);
      }

      const client = getS3Client();
      const bucket = secretValue(R2_BUCKET_NAME);

      for (const [bookId, bookKeys] of keysByBookId) {
        try {
          await assertBookMember(uid, bookId);
        } catch (error) {
          // Best-effort per PhotoStorageService.deletePhotos' contract: skip
          // keys this caller isn't authorized for rather than failing the
          // whole batch over one bad book.
          console.warn(`Skipping delete for unauthorized book ${bookId}`, error);
          continue;
        }

        await Promise.all(
            bookKeys.map((key) =>
              client
                  .send(new DeleteObjectCommand({Bucket: bucket, Key: key}))
                  .catch((error) => {
                    console.warn(`Could not delete ${key}`, error);
                  }),
            ),
        );
      }

      return {ok: true};
    },
);
