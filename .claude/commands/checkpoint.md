---
description: Run flutter analyze, fix issues, then commit with a described message
allowed-tools: Bash(flutter *), Bash(git *)
argument-hint: <commit message>
---

# Checkpoint

1. Run `flutter analyze` in the project root.
2. If there are analyzer issues, fix them. Show me what you fixed and why.
3. Run `flutter analyze` again to confirm zero issues.
4. Run `git add -A` then `git commit -m "$ARGUMENTS"`.
5. Show the short commit hash and a one-line summary of what changed.

Do not commit if analyzer issues remain. Tell me what is still broken.
