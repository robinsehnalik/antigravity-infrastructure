# Hook Mechanisms - Deep Dive

Technical deep dive into how the UserPromptSubmit and PreToolUse hooks work.

## Table of Contents

- [UserPromptSubmit Hook Flow](#userpromptsubmit-hook-flow)
- [PreToolUse Hook Flow](#pretooluse-hook-flow)
- [Exit Code Behavior (CRITICAL)](#exit-code-behavior-critical)
- [Session State Management](#session-state-management)
- [Performance Considerations](#performance-considerations)

---

## UserPromptSubmit Hook Flow

### Execution Sequence

```
User submits prompt
    ↓
.agents/settings.json registers hook
    ↓
skill-activation-prompt.sh executes
    ↓
npx tsx skill-activation-prompt.ts
    ↓
Hook reads stdin (JSON with prompt)
    ↓
Loads skill-rules.json
    ↓
Matches keywords + intent patterns
    ↓
Groups matches by priority (critical → high → medium → low)
    ↓
Outputs formatted message to stdout
    ↓
stdout becomes ephemeral context for Antigravity (injected before prompt)
    ↓
Antigravity sees: [skill suggestion] + user's prompt
```

### Key Points

- **Exit code**: Always 0 (allow)
- **stdout**: → Antigravity's context (injected as ephemeral step)
- **Timing**: Runs BEFORE Antigravity processes prompt
- **Behavior**: Non-blocking, advisory only
- **Purpose**: Make Antigravity aware of relevant skills

### Input Format

```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/transcript.json",
  "cwd": "/root/git/your-project",
  "permission_mode": "normal",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "how does the layout system work?"
}
```

### Output Format (to stdout)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 SKILL ACTIVATION CHECK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📚 RECOMMENDED SKILLS:
  → project-catalog-developer

ACTION: Use Skill tool BEFORE responding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Antigravity sees this output as additional context before processing the user's prompt.

---

## PreToolUse Hook Flow

### Execution Sequence

```
Antigravity calls replace_file_content or write_to_file tool
    ↓
.agents/hooks.json registers PreToolUse hook (agy-pre-tool-use.sh)
    ↓
skill-verification-guard executes
    ↓
npx tsx skill-verification-guard.ts
    ↓
Hook reads stdin (JSON with tool_name, tool_input)
    ↓
Loads skill-rules.json
    ↓
Checks file path patterns (glob matching)
    ↓
Reads file for content patterns (if file exists)
    ↓
Checks session state (was skill already used?)
    ↓
Checks skip conditions (file markers, env vars)
    ↓
IF MATCHED AND NOT SKIPPED:
  Update session state (mark skill as enforced)
  Output deny JSON {"decision": "deny", "reason": "..."}
ELSE:
  Output allow JSON {"decision": "allow"}
    ↓
IF DENIED:
  Antigravity receives deny reason
  Tool does NOT execute
  Antigravity must use skill and retry
IF ALLOWED:
  Tool executes normally
```

### Key Points

- **Deny Decision**: BLOCK (returns JSON deny decision to Antigravity)
- **Allow Decision**: ALLOW (tool proceeds)
- **Timing**: Runs BEFORE tool execution
- **Session tracking**: Prevents repeated blocks in same session
- **Fail open**: On errors, allows operation (don't break workflow)
- **Purpose**: Enforce critical guardrails

### Input Format

```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/transcript.json",
  "cwd": "/root/git/your-project",
  "permission_mode": "normal",
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/root/git/your-project/form/src/services/user.ts",
    "old_string": "...",
    "new_string": "..."
  }
}
```

### Output Format (to stderr when blocked)

The examples below use a hypothetical `database-verification` guardrail skill to illustrate the block flow (this repo ships `frontend-dev-guidelines` as its `block` guardrail):

```
⚠️ BLOCKED - Database Operation Detected

📋 REQUIRED ACTION:
1. Use Skill tool: 'database-verification'
2. Verify ALL table and column names against schema
3. Check database structure with DESCRIBE commands
4. Then retry this edit

Reason: Prevent column name errors in Prisma queries
File: form/src/services/user.ts

💡 TIP: Add '// @skip-validation' comment to skip future checks
```

Antigravity receives this message and understands it needs to use the skill before retrying the edit.

---

## Decision Behavior (CRITICAL)

### Decision Reference Table

| Hook Event | Return Format | Tool Execution | Antigravity Sees |
|------------|---------------|----------------|------------------|
| PreInvocation | `{"injectSteps": [{"ephemeralMessage": "..."}]}` | N/A | Injected ephemeral step |
| PreToolUse (Allow) | `{"decision": "allow"}` | **Proceeds** | Tool execution output |
| PreToolUse (Deny) | `{"decision": "deny", "reason": "..."}` | **BLOCKED** | Deny reason explanation |

### Why Deny Decision Matters

This is THE critical mechanism for enforcement:

1. **Direct enforcement** returned via Antigravity PreToolUse hook protocol
2. Reason is fed back to Antigravity immediately
3. Antigravity sees the reason and understands what to do
4. Tool execution is prevented until prerequisites are met
5. Critical for enforcement of guardrails

### Example Conversation Flow

```
User: "Add a new user service with Prisma"

Antigravity: "I'll create the user service..."
    [Attempts to call replace_file_content on form/src/services/user.ts]

PreToolUse Hook: [Deny Decision]
    reason: "⚠️ BLOCKED - Use database-verification"

Antigravity sees error, responds:
    "I need to verify the database schema first."
    [Reads skill: database-verification]
    [Verifies column names]
    [Retries edit - now allowed (session tracking)]
```

---

## Session State Management

### Purpose

Prevent repeated nagging in the same session - once Antigravity uses a skill, don't block again.

### State File Location

`.agents/hooks/state/skills-used-{session_id}.json`

### State File Structure

```json
{
  "skills_used": [
    "database-verification",
    "error-tracking"
  ],
  "files_verified": []
}
```

### How It Works

1. **First edit** of file with Prisma:
   - Hook blocks with deny decision
   - Updates session state: adds "database-verification" to skills_used
   - Antigravity sees message, uses skill

2. **Second edit** (same session):
   - Hook checks session state
   - Finds "database-verification" in skills_used
   - Returns allow decision
   - No block to Antigravity

3. **Different session**:
   - New session ID = new state file
   - Hook blocks again

### Limitation

The hook cannot detect when the skill is *actually* invoked - it just blocks once per session per skill. This means:

- If Antigravity doesn't use the skill but makes a different edit, it won't block again
- Trust that Antigravity follows the instruction
- Future enhancement: detect actual Skill tool usage

---

## Performance Considerations

### Target Metrics

- **UserPromptSubmit**: < 100ms
- **PreToolUse**: < 200ms

### Performance Bottlenecks

1. **Loading skill-rules.json** (every execution)
   - Future: Cache in memory
   - Future: Watch for changes, reload only when needed

2. **Reading file content** (PreToolUse)
   - Only when contentPatterns configured
   - Only if file exists
   - Can be slow for large files

3. **Glob matching** (PreToolUse)
   - Regex compilation for each pattern
   - Future: Compile once, cache

4. **Regex matching** (Both hooks)
   - Intent patterns (UserPromptSubmit)
   - Content patterns (PreToolUse)
   - Future: Lazy compile, cache compiled regexes

### Optimization Strategies

**Reduce patterns:**
- Use more specific patterns (fewer to check)
- Combine similar patterns where possible

**File path patterns:**
- More specific = fewer files to check
- Example: `form/src/services/**` better than `form/**`

**Content patterns:**
- Only add when truly necessary
- Simpler regex = faster matching

---

**Related Files:**
- [SKILL.md](SKILL.md) - Main skill guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Debug hook issues
- [SKILL_RULES_REFERENCE.md](SKILL_RULES_REFERENCE.md) - Configuration reference
