---
description: Show current project status — what works, what is broken, what is next
allowed-tools: Bash(flutter *), Bash(git *), Read, Glob
---

# Project status

1. Run `flutter analyze` and report the result (clean or number of issues).
2. Run `git log --oneline -5` to show recent commits.
3. Run `git status --short` to show uncommitted changes.
4. Check the vertical slice checklist from `docs/PRODUCT_SPEC.md` §21:
   - For each step (authenticate, create book, add memory, save, restart, photos visible, edit, delete), state whether it works, is partially done, or not started — based on the code you can see, not guesses.
5. List the top 1–3 things to work on next.

Keep the output short. No filler.
