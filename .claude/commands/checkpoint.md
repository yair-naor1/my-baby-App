---
description: Analyze, check spec alignment, update docs if needed, then commit
allowed-tools: Bash(flutter *), Bash(git *)
argument-hint: <commit message>
---

# Checkpoint

## Step 1 — Analyze
Run `flutter analyze`. If there are issues, fix them and show me what you fixed.
Run again to confirm zero issues.

## Step 2 — Check spec alignment
Look at the files changed since the last commit (`git diff --name-only HEAD`).
Read `docs/PRODUCT_SPEC.md` and check:

- Did any change resolve or affect an open decision from §10? If yes, update §10
  and move the decision to the correct section of the spec.
- Did any change contradict what the spec says (data model, UX flow, architecture)?
  If yes, either flag it to me and stop, or update the spec if the code is
  intentionally moving forward.
- Did any change add something not covered by the spec? If yes, add a brief note
  to the relevant section.

Show me any spec changes you made and why, before proceeding.

## Step 3 — Commit
Run `git add -A` then `git commit -m "$ARGUMENTS"`.
Show the short commit hash and a one-line summary.

Do not commit if analyzer issues remain or if there is an unresolved spec conflict.
Tell me what is still open.
