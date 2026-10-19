---
name: source-command-verify-setup
description: Run the Antigravity infrastructure health check and fix anything that fails
---

# source-command-verify-setup

Use this skill when the user asks to run the verify-setup diagnostic or health check.

## Command Template

Run the Antigravity infrastructure health check and get it fully green.

## Steps

1. Run the health check from the project root:
   ```bash
   bash .agents/scripts/verify-setup.sh
   ```

2. For every `[FAIL]` line, apply the printed fix. Common fixes:
   - Dependencies missing: `cd .agents/hooks && npm install`
   - Scripts not executable: `chmod +x .agents/hooks/*.sh .agents/scripts/*.sh`
   - Invalid JSON in `.agents/hooks.json` or `.agents/skills/skill-rules.json`: read the file, find the syntax error, and repair it.

3. Re-run the script after each fix until it reports 0 failed.

4. `[WARN]` lines are optional features (session intelligence, jq-based file tracking, AI classification keys). Summarize what each warning means and let the user decide.

5. Report the final result to the user: what was broken, what was fixed, and remaining status.
