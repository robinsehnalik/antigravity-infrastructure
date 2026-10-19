#!/bin/bash
# Antigravity (agy) PostToolUse hook adapter
# Runs post-tool-use-tracker after file changes and returns empty object {}

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    tool_name=$(printf '%s' "$INPUT" | jq -r '.toolCall.name // ""')
    target_file=$(printf '%s' "$INPUT" | jq -r '.toolCall.args.TargetFile // .toolCall.args.targetFile // .toolCall.args.file // ""')
    conversation_id=$(printf '%s' "$INPUT" | jq -r '.conversationId // "default"')
    workspace_path=$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // ""')

    if [ -n "$workspace_path" ]; then
        export AGY_PROJECT_DIR="$workspace_path"
    fi

    # Forward mapped event to tracker
    if [ -n "$target_file" ]; then
        TRACKER_INPUT=$(jq -cn --arg sid "$conversation_id" --arg tn "$tool_name" --arg fp "$target_file" \
            '{session_id: $sid, tool_name: $tn, tool_input: {file_path: $fp}}')
        printf '%s' "$TRACKER_INPUT" | bash "$SCRIPT_DIR/post-tool-use-tracker.sh" >/dev/null 2>&1 || true
    fi
fi

echo "{}"
