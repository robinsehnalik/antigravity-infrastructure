#!/bin/bash
# Antigravity (agy) Stop hook adapter
# Runs session-doc-updater / cleanup on turn stop

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

if [ -f "$SCRIPT_DIR/session-doc-updater.sh" ]; then
    printf '%s' "$INPUT" | bash "$SCRIPT_DIR/session-doc-updater.sh" >/dev/null 2>&1 || true
fi

echo '{"decision": ""}'
