const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {GoogleGenAI} = require("@google/genai");

const geminiApiKey = defineSecret("GEMINI_API_KEY");

const MAX_INPUT_LENGTH = 2000;

// Lightest model in the Gemini free tier (no billing account required) —
// this is a short bounded rewrite task, not deep reasoning, so the
// cheapest capable model is the right fit for "light AI usage, no payment".
const MODEL = "gemini-2.5-flash-lite";

// PRODUCT_SPEC.md §15 "The role of AI": explicit, opt-in only, must never
// invent facts/milestones or change meaning. This prompt is the enforcement
// point for that rule — it's the only thing standing between "helpful
// phrasing polish" and "AI rewrites the parent's story", so keep the
// constraints here strict and explicit rather than relying on model good
// behavior alone.
const SYSTEM_INSTRUCTION = `You help a parent polish a short journal entry for their baby's memory book before it appears in a printed photo album.

Rewrite the parent's text into exactly 3 alternative versions. Rules, all mandatory:
- Fix grammar, spelling, and punctuation.
- Improve flow and readability so it reads well as an album caption.
- Preserve every fact, detail, name, and meaning exactly as stated. Do not invent, assume, or add any detail, milestone, event, or emotion that isn't already in the original text.
- Do not significantly change the length — a short note stays short, a longer story stays a story.
- Write in the same language as the input (do not translate).
- Each of the 3 versions must be meaningfully different in phrasing/style from the others, not just single-word swaps.

Respond with ONLY a JSON array of exactly 3 strings, no other text, no markdown code fences.`;

exports.enhanceMemoryText = onCall(
    {secrets: [geminiApiKey], region: "us-central1"},
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

      const apiKeyValue = geminiApiKey.value();
      console.log(
          "GEMINI_API_KEY diagnostic:",
          "type=" + typeof apiKeyValue,
          "length=" + (apiKeyValue ? apiKeyValue.length : 0),
      );

      const ai = new GoogleGenAI({apiKey: apiKeyValue});

      let response;
      try {
        response = await ai.models.generateContent({
          model: MODEL,
          config: {
            systemInstruction: SYSTEM_INSTRUCTION,
          },
          contents: text,
        });
      } catch (error) {
        console.error("Gemini API call failed", error);
        throw new HttpsError("internal", "Could not reach the writing assistant.");
      }

      let suggestions;
      try {
        suggestions = JSON.parse(response.text);
      } catch (error) {
        console.error("Could not parse model response", response.text);
        throw new HttpsError("internal", "Could not parse suggestions.");
      }

      if (
        !Array.isArray(suggestions) ||
        suggestions.some((s) => typeof s !== "string")
      ) {
        throw new HttpsError("internal", "Unexpected response shape.");
      }

      return {suggestions};
    },
);
