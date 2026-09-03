const {onSchedule} = require("firebase-functions/v2/scheduler");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");

// 3+ weeks with no new memory triggers a nudge. Once triggered, don't nudge
// again for at least this long even if still inactive — otherwise it'd fire
// every single day once past the threshold.
const INACTIVITY_THRESHOLD_DAYS = 21;
const INACTIVITY_RENOTIFY_COOLDOWN_DAYS = 14;

function daysBetween(earlier, later) {
  return (later.getTime() - earlier.getTime()) / (1000 * 60 * 60 * 24);
}

/**
 * Same day-of-month as [birthDate], capped to the last day of the current
 * month — handles a Jan 31 birth date correctly in a 30/28/29-day month
 * instead of never matching.
 */
function isMonthlyAnniversary(birthDate, now) {
  const lastDayOfNowMonth = new Date(
      now.getFullYear(), now.getMonth() + 1, 0,
  ).getDate();
  const targetDay = Math.min(birthDate.getDate(), lastDayOfNowMonth);

  return now.getDate() === targetDay;
}

/** Same month + day-of-month, with the same end-of-month capping. */
function isYearlyAnniversary(birthDate, now) {
  const lastDayOfNowMonth = new Date(
      now.getFullYear(), birthDate.getMonth() + 1, 0,
  ).getDate();
  const targetDay = Math.min(birthDate.getDate(), lastDayOfNowMonth);

  return now.getMonth() === birthDate.getMonth() && now.getDate() === targetDay;
}

function monthsSinceBirth(birthDate, now) {
  let months =
    (now.getFullYear() - birthDate.getFullYear()) * 12 +
    (now.getMonth() - birthDate.getMonth());

  if (now.getDate() < birthDate.getDate()) months--;

  return Math.max(months, 0);
}

/**
 * Sends [body] to every FCM token registered to any of [ownerIds] — a book
 * can have more than one parent (spec §11), and a parent can have more than
 * one device. [data.bookId] lets the client deep-link into that book's Add
 * Memory flow on tap (spec §7.6).
 */
async function sendToBookOwners(db, ownerIds, bookId, body) {
  const tokens = [];

  for (const uid of ownerIds) {
    const userDoc = await db.collection("users").doc(uid).get();
    const userTokens = (userDoc.data() && userDoc.data().fcmTokens) || [];
    tokens.push(...userTokens);
  }

  const uniqueTokens = [...new Set(tokens)];

  if (uniqueTokens.length === 0) return;

  try {
    await admin.messaging().sendEachForMulticast({
      tokens: uniqueTokens,
      notification: {title: "Baby Book", body},
      data: {bookId},
    });
  } catch (error) {
    // Best-effort — one book's failed notification shouldn't stop the
    // scheduled run from processing the rest.
    logger.error(`Failed sending notification for book ${bookId}`, error);
  }
}

exports.sendBookReminders = onSchedule(
    {schedule: "every day 09:00", timeZone: "Asia/Jerusalem"},
    async () => {
      const db = admin.firestore();
      const now = new Date();

      const booksSnapshot = await db.collection("books").get();

      for (const bookDoc of booksSnapshot.docs) {
        const book = bookDoc.data();
        const ownerIds = book.ownerIds || [];
        const birthDate = book.birthDate && book.birthDate.toDate();

        if (!birthDate || ownerIds.length === 0) continue;

        const months = monthsSinceBirth(birthDate, now);

        // Monthly for the first year, yearly after — not both, and never
        // re-sent for the same month/year bucket even if the schedule runs
        // more than once around the boundary.
        if (months >= 1 && months <= 12 && isMonthlyAnniversary(birthDate, now)) {
          if (book.lastMonthlyNotifiedMonth !== months) {
            await sendToBookOwners(
                db, ownerIds, bookDoc.id,
                `${book.childName} is ${months} month${months === 1 ? "" : "s"} old! What's new?`,
            );
            await bookDoc.ref.update({lastMonthlyNotifiedMonth: months});
          }
        } else if (months > 12 && isYearlyAnniversary(birthDate, now)) {
          const years = Math.floor(months / 12);

          if (book.lastYearlyNotifiedYear !== years) {
            await sendToBookOwners(
                db, ownerIds, bookDoc.id,
                `${book.childName} is turning ${years}! What's new?`,
            );
            await bookDoc.ref.update({lastYearlyNotifiedYear: years});
          }
        }

        // Inactivity nudge — independent of the birthday checks above, so
        // both can fire on the same day if they both apply.
        const lastMemorySnapshot = await bookDoc.ref
            .collection("memories")
            .orderBy("createdAt", "desc")
            .limit(1)
            .get();

        if (lastMemorySnapshot.empty) continue;

        const lastMemoryCreatedAt = lastMemorySnapshot.docs[0].data().createdAt;
        if (!lastMemoryCreatedAt) continue;

        const daysSinceLastMemory = daysBetween(lastMemoryCreatedAt.toDate(), now);

        if (daysSinceLastMemory < INACTIVITY_THRESHOLD_DAYS) continue;

        const lastNudgeAt = book.lastInactivityNotifiedAt;
        const daysSinceLastNudge = lastNudgeAt ?
          daysBetween(lastNudgeAt.toDate(), now) :
          Infinity;

        if (daysSinceLastNudge < INACTIVITY_RENOTIFY_COOLDOWN_DAYS) continue;

        await sendToBookOwners(
            db, ownerIds, bookDoc.id,
            `It's been a while since you added a memory to ${book.childName}'s book.`,
        );
        await bookDoc.ref.update({
          lastInactivityNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    },
);
