#!/bin/bash
# Stop hook - session doc indexing + stale session-state pruning

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${AGY_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Prune per-session state files and caches older than 7 days.
if [ -d "$PROJECT_DIR/.agents/hooks/state" ]; then
    find "$PROJECT_DIR/.agents/hooks/state" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
fi
if [ -d "$PROJECT_DIR/.agents/hooks/cache" ]; then
    find "$PROJECT_DIR/.agents/hooks/cache" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
fi

# Skip doc indexing if disabled
if [ "$SESSION_DOCS_ENABLED" = "false" ]; then
    cat >/dev/null
    exit 0
fi

exec "$(dirname "$0")/_run-node-hook.sh" session-doc-updater.ts
