#!/bin/bash
# Antigravity (agy) PreInvocation hook adapter
# Intercepts prompt submission in Antigravity, determines active skills,
# and injects skill activation context as an ephemeralMessage.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

# Fail-open if jq is missing
if ! command -v jq >/dev/null 2>&1; then
    echo "{}"
    exit 0
fi

conversation_id=$(printf '%s' "$INPUT" | jq -r '.conversationId // ""')
transcript_path=$(printf '%s' "$INPUT" | jq -r '.transcriptPath // ""')
workspace_path=$(printf '%s' "$INPUT" | jq -r '.workspacePaths[0] // ""')

if [ -n "$workspace_path" ]; then
    export AGY_PROJECT_DIR="$workspace_path"
fi

# Extract the user prompt from transcript if present
PROMPT=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # Grab the latest USER_INPUT content
    raw_prompt=$(grep '"type":"USER_INPUT"' "$transcript_path" 2>/dev/null | tail -n 1 | jq -r '.content // ""' 2>/dev/null || true)
    if [ -n "$raw_prompt" ]; then
        # Strip XML user tags if present
        PROMPT=$(printf '%s' "$raw_prompt" | sed -e 's/<USER_REQUEST>//g' -e 's/<\/USER_REQUEST>//g' | awk '/<ADDITIONAL_METADATA>/{exit} {print}' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
fi

# If no prompt extracted or prompt is empty, return empty response
if [ -z "$PROMPT" ]; then
    echo "{}"
    exit 0
fi

# Run the skill activation classifier
HOOK_INPUT=$(jq -cn --arg sid "${conversation_id:-default}" --arg p "$PROMPT" \
    '{session_id: $sid, prompt: $p}')

SUGGESTIONS=$(printf '%s' "$HOOK_INPUT" | bash "$SCRIPT_DIR/skill-activation-prompt.sh" 2>/dev/null || true)

# If suggestions were generated, format for Antigravity injectSteps
if [ -n "$SUGGESTIONS" ] && [ "$SUGGESTIONS" != "{}" ]; then
    jq -cn --arg msg "$SUGGESTIONS" '{
        injectSteps: [
            {
                ephemeralMessage: $msg
            }
        ]
    }'
else
    echo "{}"
fi
