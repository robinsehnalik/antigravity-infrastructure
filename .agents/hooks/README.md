# Hooks

Antigravity hooks that enable skill auto-activation, file tracking, and validation.

---

## What Are Hooks?

Hooks are scripts that run at specific points in Antigravity's workflow:
- **PreInvocation**: When user submits a prompt
- **PreToolUse**: Before a tool executes  
- **PostToolUse**: After a tool completes
- **Stop**: When turn or session finishes

**Key insight:** Hooks can modify prompts, block actions, and track state - enabling features Antigravity can't do alone.

---

## Essential Hooks (Start Here)

### skill-activation-prompt (PreInvocation)

**Purpose:** Automatically suggests relevant skills based on user prompts and file context

**How it works:**
1. Reads `skill-rules.json`
2. Matches user prompt against trigger patterns
3. Checks which files user is working with
4. Injects skill suggestions into Antigravity's context

**Why it's essential:** This is THE hook that makes skills auto-activate.

**Integration:**
```bash
# Make executable
chmod +x .agents/hooks/*.sh

# Install dependencies
cd .agents/hooks
npm install
```

**Add to hooks.json:**
```json
{
  "hooks": {
    "PreInvocation": [
      {
        "command": "$AGY_PROJECT_DIR/.agents/hooks/agy-pre-invocation.sh"
      }
    ]
  }
}
```

**Customization:** ✅ None needed - reads skill-rules.json automatically

---

### post-tool-use-tracker (PostToolUse)

**Purpose:** Tracks file changes to maintain context across sessions

**How it works:**
1. Monitors replace_file_content and write_to_file tool calls
2. Records which files were modified
3. Creates cache for context management
4. Auto-detects project structure (frontend, backend, packages, etc.)

**Why it's essential:** Helps Antigravity understand what parts of your codebase are active.

**Integration:**
```bash
# Make executable
chmod +x .agents/hooks/*.sh
```

**Add to hooks.json:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "replace_file_content|write_to_file",
        "command": "$AGY_PROJECT_DIR/.agents/hooks/agy-post-tool-use.sh"
      }
    ]
  }
}
```

**Customization:** ✅ None needed - auto-detects structure

---

### skill-verification-guard (PreToolUse)

**Purpose:** Enforces mandatory skill activation before replace_file_content/write_to_file (v2.0)

**How it works:**
1. Checks whether mandatory skills (flagged by skill-activation-prompt) are still pending
2. First edit attempt: BLOCKED with a deny decision, pending list cleared
3. Second attempt: allowed (two-try model)
4. Optionally analyzes the code being written for skill suggestions (AI mode)

**Why it's essential:** Suggestions alone get ignored; this provides the enforcement.

**Integration:** registered under `PreToolUse` in `.agents/hooks.json` via `agy-pre-tool-use.sh`.

**Customization:** ✅ None needed. Env switches: `SKIP_MANDATORY_SKILLS=true` to bypass, `PRETOOLUSE_SOFT_BLOCK=true` for soft mode.

---

### skill-activation-tracker (PostToolUse)

**Purpose:** Clears skills from the pending list once they're actually activated (v2.0)

**Why it's essential:** Without it, the guard would keep blocking even after you activated the skill.

**Integration:** wired into `agy-post-tool-use.sh` / `.agents/hooks.json`.

**Customization:** ✅ None needed

---

## Optional Hooks (Require Customization)

### tsc-check (Stop)

**Purpose:** TypeScript compilation check when user stops

**⚠️ WARNING:** Configured for multi-service monorepo structure

**Integration:**

**First, determine if this is right for you:**
- ✅ Use if: Multi-service TypeScript monorepo
- ❌ Skip if: Single-service project or different build setup

**If using:**
1. Copy tsc-check.sh
2. **EDIT the service detection (line ~28):**
   ```bash
   # Replace example services with YOUR services:
   case "$repo" in
       api|web|auth|payments|...)  # ← Your actual services
   ```
3. Test manually before adding to settings.json

**Customization:** ⚠️⚠️⚠️ Heavy

---

### trigger-build-resolver (Stop)

**Purpose:** Auto-launches auto-error-resolver agent when compilation fails

**Depends on:** tsc-check hook working correctly

**Customization:** ✅ None (but tsc-check must work first)

---

### stop-build-check-enhanced (Stop)

**Purpose:** Alternative Stop-hook build check with error summaries fed back to Antigravity

**Customization:** ⚠️ Moderate - expects a TypeScript build setup; review before enabling

---

### error-handling-reminder (Stop)

**Purpose:** Reminds Antigravity to add error handling/Sentry coverage for files edited this session

**Customization:** ⚠️ Moderate - assumes the tsc-cache tracking from post-tool-use-tracker

---

### session-doc-updater (Stop)

**Purpose:** Part of the session-intelligence system - indexes your active dev-docs task (plan/context files) into a local vector DB so past session knowledge is searchable

**Installed by default** in `.agents/hooks.json`, but it no-ops instantly until you set up session indexing (it requires `data/sessions.db`, created by `.agents/scripts/index-sessions.ts`, plus a `dev/active/` task and a `GEMINI_API_KEY` for embeddings). See [CONFIG.md](CONFIG.md).

**Customization:** ✅ None needed. Disable any time with `SESSION_DOCS_ENABLED=false`.

---

## For Antigravity

**When setting up hooks for a user:**

1. **Read [README.md](../../README.md)** first
2. **Always start with the four essential hooks**
3. **Ask before adding Stop hooks** - they can block if misconfigured  
4. **Verify after setup:**
   ```bash
   ls -la .agents/hooks/*.sh | grep rwx
   ```

**Questions?** See [README.md](../../README.md)
