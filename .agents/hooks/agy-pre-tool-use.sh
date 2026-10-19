#!/bin/bash
# Antigravity (agy) PreToolUse hook adapter
# Runs skill-verification-guard before replace_file_content or write_to_file.
# Returns {"decision": "allow"} or {"decision": "deny", "reason": "..."}

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    echo '{"decision": "allow"}'
    exit 0
fi

tool_name=$(printf '%s' "$INPUT" | jq -r '.toolCall.name // ""')
target_file=$(printf '%s' "$INPUT" | jq -r '.toolCall.args.TargetFile // .toolCall.args.targetFile // .toolCall.args.file // ""')
conversation_id=$(printf '%s' "$INPUT" | jq -r '.conversationId // "default"')
workspace_path=$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // ""')

if [ -n "$workspace_path" ]; then
    export AGY_PROJECT_DIR="$workspace_path"
fi

# Only gate file modification tools
case "$tool_name" in
    replace_file_content|write_to_file)
        ;;
    *)
        echo '{"decision": "allow"}'
        exit 0
        ;;
esac

if [ -z "$target_file" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Map to Edit event for skill-verification-guard
GUARD_INPUT=$(jq -cn --arg sid "$conversation_id" --arg fp "$target_file" \
    '{session_id: $sid, tool_name: "Edit", tool_input: {file_path: $fp}}')

# Execute guard and capture output + stderr
TMP_ERR=$(mktemp)
set +e
printf '%s' "$GUARD_INPUT" | bash "$SCRIPT_DIR/skill-verification-guard.sh" 2>"$TMP_ERR"
rc=$?
set -e

ERR_MSG=$(cat "$TMP_ERR" 2>/dev/null || true)
rm -f "$TMP_ERR"

if [ "$rc" -eq 2 ]; then
    # Blocked by guardrail
    if [ -z "$ERR_MSG" ]; then
        ERR_MSG="Blocked by skill guardrail. Required skill must be consulted before modifying $target_file."
    fi
    jq -cn --arg reason "$ERR_MSG" '{decision: "deny", reason: $reason}'
else
    echo '{"decision": "allow"}'
fi
