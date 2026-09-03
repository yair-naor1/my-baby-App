const {onCall, HttpsError} = require("firebase-functions/v2/https");

// Set by Firebase at deploy/runtime for the function's own project.
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;

const MAX_INPUT_LENGTH = 2000;

// Free-tier-eligible on the Developer API, but that API's newly-issued "AQ."
// keys are currently broken Google-side (401 ACCESS_TOKEN_TYPE_UNSUPPORTED,
// confirmed as an active, acknowledged bug on Google's AI Developer Forum,
// not something in this code — see PRODUCT_SPEC.md §20). Calling the same
// model via Vertex AI instead, authenticated with this Cloud Function's own
// service-account identity (no API key at all), sidesteps that bug entirely.
// 2.5 Flash-Lite retires 2026-10-16; 3.1 Flash-Lite is its GA replacement.
const MODEL = "gemini-3.1-flash-lite";

// Gemini 3.1 Flash-Lite is only available on Vertex AI's "global" endpoint,
// not a region-pinned one (confirmed: gemini-3.1-flash-lite 404s under
// locations/us-central1) — no region in the hostname, "global" in the path.
const VERTEX_ENDPOINT =
  `https://aiplatform.googleapis.com/v1/projects/${PROJECT_ID}` +
  `/locations/global/publishers/google/models/${MODEL}:generateContent`;

// PRODUCT_SPEC.md §15 "The role of AI": explicit, opt-in only, must never
// invent facts/milestones or change meaning. This prompt is the enforcement
// point for that rule — it's the only thing standing between "helpful
// phrasing polish" and "AI rewrites the parent's story", so keep the
// constraints here strict and explicit rather than relying on model good
// behavior alone.
const SYSTEM_INSTRUCTION = `You polish short memory notes that a parent wrote about their baby, for their memory book. You are an editor, not a writer — the memory belongs to the parent.

HARD RULES — never break these:
1. Never add a fact, detail, sensory description, emotion, person, place, or time that is not already in the original text. Do not assume or infer anything beyond what is written.
2. Never remove a fact the parent wrote.
3. Never change names, numbers, dates, ages, or measurements.
4. Reply in the same language as the input. Never translate.
5. If the input is very short or already clean and complete, most or all of your 3 versions may be identical (or nearly identical) to the original — do not pad or elaborate just to have something to show.
6. If a "Grammar context" note is given below, use it only to get Hebrew verb/adjective gender agreement right when the input is Hebrew. Never mention the child's gender, name, or the note itself in your output unless the parent's own original text already did.

LENGTH — stay close to the original's length:
- "natural": within about 10% of the original length, shorter or longer.
- "warm": at most about 1.4x the original length.
- "playful": at most about 0.8x the original length.

STYLES:
- "natural": light touch — fix grammar/spelling only, keep the parent's own sentence structure and word choices wherever possible. If the text is already correct, return it unchanged.
- "warm": more feeling than the original, but still sounds like a real, tired parent jotting this down — not a greeting card.
- "playful": shorter, lighter, works as a caption.

The single biggest failure mode to avoid, in every style: sounding like AI-generated text instead of something a real parent actually wrote. Concretely, all mandatory:
- No cliché baby-journal phrases — "little one", "precious moment", "heart melted", "filled with joy", "priceless", "growing up so fast", "cherish this", "bundle of joy", or anything in that family — unless the parent's own original text already used it.
- No stacked adjectives or adverbs ("so incredibly, wonderfully happy"). One honest word beats three flowery ones.
- No added exclamation points or emotional intensifiers the parent didn't use themselves.
- Vary sentence length like real writing does — don't produce neat, symmetrical, evenly-balanced sentences.
- Write in first person, as the parent — never as a narrator describing the parent from outside.
- Contractions and casual phrasing are welcome where they'd sound natural.
- Each of the 3 versions must read like a genuinely different way a real parent might phrase this, not the same generic paragraph with synonyms swapped in.
- Hebrew input must read naturally and casually in Hebrew — every rule above applies there too, not just in English.

Output only the structured result. No markdown, no commentary, no explanation of what you changed.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    options: {
      type: "ARRAY",
      minItems: 3,
      maxItems: 3,
      items: {
        type: "OBJECT",
        properties: {
          style: {type: "STRING", enum: ["natural", "warm", "playful"]},
          text: {type: "STRING"},
        },
        required: ["style", "text"],
      },
    },
  },
  required: ["options"],
};

/**
 * Fetches a short-lived OAuth access token for this Cloud Function's own
 * service-account identity from the metadata server — no npm dependency
 * needed (avoids reintroducing the package bloat/auto-detection complexity
 * that caused the earlier @google/genai issues).
 */
async function getAccessToken() {
  const response = await fetch(
      "http://metadata.google.internal/computeMetadata/v1/instance/" +
      "service-accounts/default/token",
      {headers: {"Metadata-Flavor": "Google"}},
  );

  if (!response.ok) {
    throw new Error(`Metadata server token fetch failed: ${response.status}`);
  }

  const data = await response.json();
  return data.access_token;
}

exports.enhanceMemoryText = onCall(
    {region: "us-central1"},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const text = (request.data && request.data.text || "").toString().trim();

      if (!text) {
        throw new HttpsError("invalid-argument", "Text is required.");
      }

      if (text.length > MAX_INPUT_LENGTH) {
        throw new HttpsError(
            "invalid-argument",
            `Text must be ${MAX_INPUT_LENGTH} characters or fewer.`,
        );
      }

      // 'male'/'female' only, for Hebrew grammatical gender — see HARD RULE 6
      // in SYSTEM_INSTRUCTION. Never required; absent for most callers today
      // since the book-level gender field is new and optional.
      const childGender = request.data && request.data.childGender;
      const genderContext = (childGender === "male" || childGender === "female")
        ? `Grammar context: the child is ${childGender}.\n\n`
        : "";
      const promptText = `${genderContext}Parent's text:\n"""\n${text}\n"""`;

      let accessToken;
      try {
        accessToken = await getAccessToken();
      } catch (error) {
        console.error("Could not fetch service-account access token", error);
        throw new HttpsError("internal", "Writing assistant is not configured.");
      }

      let apiResponse;
      try {
        apiResponse = await fetch(VERTEX_ENDPOINT, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            systemInstruction: {parts: [{text: SYSTEM_INSTRUCTION}]},
            contents: [{role: "user", parts: [{text: promptText}]}],
            generationConfig: {
              // Moderate rather than default-creative: a fabricated detail
              // is a spec §15 violation, not just a quality nitpick, so this
              // errs conservative even though it costs some of the "warm"/
              // "playful" variety a higher temperature would give.
              temperature: 0.5,
              responseMimeType: "application/json",
              responseSchema: RESPONSE_SCHEMA,
            },
          }),
        });
      } catch (error) {
        console.error("Vertex AI request failed", error);
        throw new HttpsError("internal", "Could not reach the writing assistant.");
      }

      if (!apiResponse.ok) {
        const errorBody = await apiResponse.text();
        console.error("Vertex AI returned an error", apiResponse.status, errorBody);
        throw new HttpsError("internal", "Could not reach the writing assistant.");
      }

      const payload = await apiResponse.json();
      const rawText = payload &&
        payload.candidates &&
        payload.candidates[0] &&
        payload.candidates[0].content &&
        payload.candidates[0].content.parts &&
        payload.candidates[0].content.parts[0] &&
        payload.candidates[0].content.parts[0].text;

      let parsed;
      try {
        parsed = JSON.parse(rawText);
      } catch (error) {
        console.error("Could not parse model response", rawText);
        throw new HttpsError("internal", "Could not parse suggestions.");
      }

      const options = parsed && parsed.options;

      if (
        !Array.isArray(options) ||
        options.length !== 3 ||
        options.some((o) => typeof o.style !== "string" || typeof o.text !== "string")
      ) {
        console.error("Unexpected response shape", parsed);
        throw new HttpsError("internal", "Unexpected response shape.");
      }

      return {options};
    },
);
