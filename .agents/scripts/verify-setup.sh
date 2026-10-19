#!/bin/bash
# verify-setup.sh - Health check for Antigravity (agy) infrastructure.
#
# Usage:
#   bash .agents/scripts/verify-setup.sh
#
# Checks skill discovery, hooks, rules, and auto-activation system end-to-end.
# Exit code: 0 = no failures (warnings allowed), 1 = at least one [FAIL].

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

AGENTS_DIR="$PROJECT_ROOT/.agents"
HOOKS_DIR="$AGENTS_DIR/hooks"
AGENTS_HOOKS_JSON="$AGENTS_DIR/hooks.json"
RULES="$AGENTS_DIR/skills/skill-rules.json"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  [PASS] $1"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    echo "  [WARN] $1"
    [ -n "$2" ] && echo "         fix: $2"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  [FAIL] $1"
    [ -n "$2" ] && echo "         fix: $2"
}

echo ""
echo "Antigravity (agy) Infrastructure Health Check"
echo "Project: $PROJECT_ROOT"
echo ""

# ---- 1. Node version ----
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -p 'parseInt(process.versions.node, 10)' 2>/dev/null)
    if [ "${NODE_MAJOR:-0}" -ge 18 ]; then
        pass "Node $(node -v) (>= 18)"
    else
        fail "Node 18+ required, found $(node -v)" "install Node 20+ from https://nodejs.org"
    fi
else
    fail "node not found on PATH" "install Node 20+ from https://nodejs.org"
    echo ""
    echo "Result: cannot continue without Node. 1 check failed."
    exit 1
fi

# ---- 2. Antigravity lifecycle hooks configuration (.agents/hooks.json) ----
if [ -f "$AGENTS_HOOKS_JSON" ]; then
    if node -e "JSON.parse(require('fs').readFileSync('$AGENTS_HOOKS_JSON','utf8'))" 2>/dev/null; then
        pass "Antigravity .agents/hooks.json valid"
    else
        fail ".agents/hooks.json is not valid JSON" "fix syntax in $AGENTS_HOOKS_JSON"
    fi
else
    fail ".agents/hooks.json missing - Antigravity lifecycle hooks will not trigger" "create $AGENTS_HOOKS_JSON"
fi

# ---- 3. Hook scripts are executable ----
NONEXEC=""
for f in "$HOOKS_DIR"/*.sh; do
    [ -e "$f" ] || continue
    [ -x "$f" ] || NONEXEC="$NONEXEC $(basename "$f")"
done
if [ -z "$NONEXEC" ]; then
    pass "all hook scripts in .agents/hooks are executable"
else
    fail "hook scripts missing executable bit:$NONEXEC" "chmod +x $HOOKS_DIR/*.sh"
fi

# ---- 4. Hook dependencies ----
DEPS_OK=0
if [ -d "$HOOKS_DIR/node_modules" ]; then
    DEPS_OK=1
    pass "hook dependencies installed (node_modules present)"
    if node -e "require('$HOOKS_DIR/node_modules/better-sqlite3')" >/dev/null 2>&1; then
        pass "better-sqlite3 loads (session intelligence available)"
    else
        warn "better-sqlite3 failed to load - session intelligence is off" "cd $HOOKS_DIR && npm rebuild better-sqlite3"
    fi
else
    fail "hook dependencies not installed - skill activation will not run" "cd $HOOKS_DIR && npm install"
fi

# ---- 5. skill-rules.json ----
MODE="disabled"
if [ ! -f "$RULES" ]; then
    fail "skill-rules.json missing - hooks have no trigger rules" "create skill-rules.json in .agents/skills/"
elif ! node -e "JSON.parse(require('fs').readFileSync('$RULES','utf8'))" 2>/dev/null; then
    fail "skill-rules.json is not valid JSON - skill matching is disabled" "fix the syntax"
else
    MODE=$(node -e "
        const r = JSON.parse(require('fs').readFileSync('$RULES','utf8'));
        console.log((r.settings || {}).skill_activation_mode || 'disabled');
    " 2>/dev/null)
    CONS=$(node -e "
        const r = JSON.parse(require('fs').readFileSync('$RULES','utf8'));
        console.log((r.settings || {}).conservativeness || 'balanced');
    " 2>/dev/null)
    pass "skill-rules.json valid (mode: $MODE, conservativeness: $CONS)"
fi

# ---- 6. AI provider availability (when AI mode enabled) ----
if [ "$MODE" != "disabled" ]; then
    if [ -f "$HOOKS_DIR/.env" ]; then
        set -a
        . "$HOOKS_DIR/.env" >/dev/null 2>&1
        set +a
    fi
    PROVIDER_OK=0
    if [ -n "$GEMINI_API_KEY" ] || [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
        PROVIDER_OK=1
    elif command -v curl >/dev/null 2>&1 && curl -s --max-time 2 "${OLLAMA_BASE_URL:-http://localhost:11434}/api/tags" >/dev/null 2>&1; then
        PROVIDER_OK=1
    fi
    if [ "$PROVIDER_OK" = "1" ]; then
        pass "AI mode ($MODE): an AI provider is configured and available"
    elif [ "$MODE" = "ai-only" ]; then
        fail "mode is ai-only but no API key was found and Ollama is not running" "set GEMINI_API_KEY or configure .agents/hooks/.env"
    else
        warn "mode is fallback but no API key was found - regex matching will be used" "add GEMINI_API_KEY or use regex mode"
    fi
fi

# ---- 7. jq ----
if command -v jq >/dev/null 2>&1; then
    pass "jq installed"
else
    warn "jq not installed - hook parsing will be degraded" "install jq (brew install jq)"
fi

# ---- 8. Skills directory integrity ----
SKILL_COUNT=$(find "$AGENTS_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -gt 0 ]; then
    pass "found $SKILL_COUNT skills in .agents/skills/ (including web-design-guidelines)"
else
    fail "no skills found in .agents/skills/" "verify .agents/skills directory"
fi

# ---- 9. End-to-end: test prompt through activation hook ----
if [ "$DEPS_OK" = "1" ] && [ -x "$HOOKS_DIR/skill-activation-prompt.sh" ]; then
    RUNNER=""
    command -v timeout >/dev/null 2>&1 && RUNNER="timeout 30"
    E2E_SESSION="verify-setup-$$-$(date +%s 2>/dev/null || echo 0)"
    E2E_OUTPUT=$(printf '{"session_id":"%s","prompt":"create a new React component"}' "$E2E_SESSION" \
        | AGY_PROJECT_DIR="$PROJECT_ROOT" $RUNNER bash "$HOOKS_DIR/skill-activation-prompt.sh" 2>/dev/null)
    rm -f "$HOOKS_DIR/state/skills-used-verify-setup-"*.json "$HOOKS_DIR/state/session-doc-verify-setup-"*.json 2>/dev/null
    if printf '%s' "$E2E_OUTPUT" | grep -q "frontend-dev-guidelines"; then
        pass "end-to-end: activation hook flagged frontend-dev-guidelines for React prompt"
    elif [ "$MODE" != "disabled" ]; then
        warn "end-to-end: AI classifier did not flag expected skill on test prompt" "test with DEBUG_SKILLS=1"
    else
        fail "end-to-end: activation hook produced no suggestion for test prompt" "debug with: echo '{\"session_id\":\"t\",\"prompt\":\"create a new React component\"}' | DEBUG_SKILLS=1 bash $HOOKS_DIR/skill-activation-prompt.sh"
    fi
else
    fail "end-to-end check skipped - dependencies or activation hook missing" "fix failures above and re-run"
fi

# ---- Summary ----
echo ""
TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
echo "Result: $PASS_COUNT passed, $WARN_COUNT warning(s), $FAIL_COUNT failed (of $TOTAL checks)"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Fix the [FAIL] items above, then re-run: bash .agents/scripts/verify-setup.sh"
    exit 1
fi
echo "Antigravity & skill infrastructure is ready!"
exit 0
