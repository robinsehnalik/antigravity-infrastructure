#!/bin/bash
# Shared preamble for the Node-based hooks.
# Usage: _run-node-hook.sh <script.ts>  (hook JSON arrives on stdin)
set -e

SCRIPT_NAME="$1"

# Read stdin first (before any sourcing that might consume it)
INPUT=$(cat)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${AGY_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export PROJECT_DIR
export AGY_PROJECT_DIR="$PROJECT_DIR"

if [ -d "$PROJECT_DIR/.agents/hooks" ]; then
    HOOKS_DIR="$PROJECT_DIR/.agents/hooks"
else
    HOOKS_DIR="$SCRIPT_DIR"
fi

# Source bashrc to pick up API keys (GEMINI_API_KEY, OPENAI_API_KEY, etc.).
if [ -f ~/.bashrc ]; then
    source ~/.bashrc </dev/null >/dev/null 2>&1 || true
fi

# Source .env for API keys (reliable path for macOS/zsh users)
if [ -f "$HOOKS_DIR/.env" ]; then
    set -a
    source "$HOOKS_DIR/.env" >/dev/null 2>&1 || true
    set +a
fi

# Fail safe if dependencies are missing. tsx is invoked directly rather than
# through npx, which adds package-resolution latency on every hook call.
TSX_BIN="$HOOKS_DIR/node_modules/.bin/tsx"
if [ ! -x "$TSX_BIN" ]; then
    echo "hooks: dependencies not installed - run: cd $HOOKS_DIR && npm install" >&2
    exit 0
fi

cd "$HOOKS_DIR"
echo "$INPUT" | "$TSX_BIN" "$SCRIPT_NAME"
