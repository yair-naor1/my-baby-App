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
const SYSTEM_INSTRUCTION = `You help a parent polish a short journal entry for their baby's memory book before it appears in a printed photo album.

Rewrite the parent's text into exactly 3 alternative versions, each in a different style:
- "natural": a polished, natural version — fix grammar/spelling/flow, keep it plain.
- "warm": a warmer, more emotional version, without inventing feelings the parent didn't express.
- "playful": a shorter, more playful/light version suited to a caption.

Rules, all mandatory:
- Preserve every fact, detail, name, and meaning exactly as stated. Do not invent, assume, or add any detail, milestone, event, or emotion that isn't already in the original text.
- Do not significantly change the length — a short note stays short, a longer story stays a story.
- Write in the same language as the input (do not translate). Hebrew input must read naturally in Hebrew.
- Keep the parent's own voice — these should sound like the parent wrote them, not like generic AI writing.`;

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
            contents: [{role: "user", parts: [{text}]}],
            generationConfig: {
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
