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

// Client picks exactly one of these per call — "Translate / Style / Fix" in
// the UI — instead of always generating 3 variants at once. See
// PRODUCT_SPEC.md §15.
const MODES = ["translate", "fix", "style"];

// Extensible on purpose — the UI's "maybe more" styles later just need an
// entry here, no other code changes.
const STYLE_INSTRUCTIONS = {
  short: `Rewrite to be noticeably shorter than the original — aim for around 60% of the length or less — while keeping every fact. Cut filler and repetition, not content.`,
  warm: `Rewrite with more warmth and feeling than the original, but still sound like a real, tired parent jotting this down — not a greeting card. At most about 1.4x the original length.`,
  playful: `Rewrite shorter and lighter — works as a caption under a photo. At most about 0.8x the original length.`,
};

// PRODUCT_SPEC.md §15 "The role of AI": explicit, opt-in only, must never
// invent facts/milestones or change meaning. This prompt is the enforcement
// point for that rule — it's the only thing standing between "helpful
// phrasing polish" and "AI rewrites the parent's story", so keep the
// constraints here strict and explicit rather than relying on model good
// behavior alone.
//
// Built per-request rather than one static prompt because "translate" must
// explicitly override the "never translate" rule the other two modes need —
// trying to express that with a single shared prompt got confusing fast.
function buildSystemInstruction({mode, style}) {
  const languageRule = mode === "translate"
    ? "4. Detect whether the input is Hebrew or English, and translate it into the other one. Keep it natural and idiomatic in the target language — not a stiff, literal, word-for-word translation."
    : "4. Reply in the same language as the input. Never translate.";

  const common = `You help a parent with a short journal entry they wrote about their baby, for their memory book. You are an editor, not a writer — the memory belongs to the parent.

HARD RULES — never break these:
1. Never add a fact, detail, sensory description, emotion, person, place, or time that is not already in the original text. Do not assume or infer anything beyond what is written.
2. Never remove a fact the parent wrote.
3. Never change names, numbers, dates, ages, or measurements — translating a date/number's format is fine, changing its value is not.
${languageRule}
5. If a "Grammar context" note is given below, use it only to get Hebrew verb/adjective gender agreement right when the input (or, in translate mode, the output) is Hebrew. Never mention the child's gender, name, or the note itself in your output unless the parent's own original text already did.

The single biggest failure mode to avoid: sounding like AI-generated text instead of something a real parent actually wrote. Concretely:
- No cliché baby-journal phrases — "little one", "precious moment", "heart melted", "filled with joy", "priceless", "growing up so fast", "cherish this", "bundle of joy", or anything in that family — unless the parent's own original text already used it.
- No stacked adjectives or adverbs ("so incredibly, wonderfully happy"). One honest word beats three flowery ones.
- No added exclamation points or emotional intensifiers the parent didn't use themselves.
- Vary sentence length like real writing does — don't produce neat, symmetrical, evenly-balanced sentences.
- Write in first person, as the parent — never as a narrator describing the parent from outside.
- Contractions and casual phrasing are welcome where they'd sound natural.

Output only the rewritten text, nothing else. No markdown, no quotation marks wrapping it, no commentary, no explanation of what you changed.`;

  if (mode === "fix") {
    return `${common}\n\nTASK: Fix only grammar, spelling, and punctuation mistakes. Do not change word choice, sentence structure, tone, or length beyond what correcting actual errors requires. If the text already has no errors, return it completely unchanged.`;
  }

  if (mode === "translate") {
    return `${common}\n\nTASK: Translate the text as described in rule 4 above.`;
  }

  // mode === "style"
  return `${common}\n\nTASK: ${STYLE_INSTRUCTIONS[style]}`;
}

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

      const mode = request.data && request.data.mode;

      if (!MODES.includes(mode)) {
        throw new HttpsError(
            "invalid-argument",
            `mode must be one of: ${MODES.join(", ")}`,
        );
      }

      const style = request.data && request.data.style;

      if (mode === "style" && !Object.prototype.hasOwnProperty.call(STYLE_INSTRUCTIONS, style)) {
        throw new HttpsError(
            "invalid-argument",
            `style must be one of: ${Object.keys(STYLE_INSTRUCTIONS).join(", ")}`,
        );
      }

      // 'male'/'female' only, for Hebrew grammatical gender — see HARD RULE 5
      // in buildSystemInstruction. Never required; absent for most callers
      // today since the book-level gender field is new and optional.
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
            systemInstruction: {
              parts: [{text: buildSystemInstruction({mode, style})}],
            },
            contents: [{role: "user", parts: [{text: promptText}]}],
            generationConfig: {
              // Moderate rather than default-creative: a fabricated detail
              // is a spec §15 violation, not just a quality nitpick.
              temperature: 0.5,
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
      const resultText = payload &&
        payload.candidates &&
        payload.candidates[0] &&
        payload.candidates[0].content &&
        payload.candidates[0].content.parts &&
        payload.candidates[0].content.parts[0] &&
        payload.candidates[0].content.parts[0].text;

      if (typeof resultText !== "string" || !resultText.trim()) {
        console.error("Unexpected response shape", payload);
        throw new HttpsError("internal", "Unexpected response shape.");
      }

      return {text: resultText.trim()};
    },
);
