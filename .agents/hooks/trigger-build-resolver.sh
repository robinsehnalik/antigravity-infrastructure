#!/bin/bash

PROJECT_DIR="${AGY_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEBUG_LOG="$PROJECT_DIR/.agents/hooks/debug.log"

# Cap the log at ~1MB - truncate before appending
if [ -f "$DEBUG_LOG" ] && [ "$(wc -c < "$DEBUG_LOG")" -gt 1048576 ]; then
    : > "$DEBUG_LOG"
fi

echo "Hook triggered at $(date)" >> "$DEBUG_LOG"
echo "Args: $@" >> "$DEBUG_LOG"
echo "Stdin:" >> "$DEBUG_LOG"
cat >> "$DEBUG_LOG"

# Add detailed debugging
echo "=== DEBUG SECTION ===" >> "$DEBUG_LOG"
echo "AGY_PROJECT_DIR: $PROJECT_DIR" >> "$DEBUG_LOG"
echo "Current working directory: $(pwd)" >> "$DEBUG_LOG"

# Define the service directories to check
services_dirs=("email" "exports" "form" "frontend" "projects" "uploads" "users" "utilities" "events" "database")
services_with_changes=()

# Check each service directory for git changes
for service in "${services_dirs[@]}"; do
    service_path="$PROJECT_DIR/$service"
    echo "Checking service: $service at $service_path" >> "$DEBUG_LOG"
    
    # Check if directory exists and is a git repo
    if [ -d "$service_path" ] && [ -d "$service_path/.git" ]; then
        echo "  -> Is a git repository" >> "$DEBUG_LOG"
        
        # Check for changes in this specific repo
        cd "$service_path"
        git_status=$(git status --porcelain 2>/dev/null)
        
        if [ -n "$git_status" ]; then
            echo "  -> Has changes:" >> "$DEBUG_LOG"
            echo "$git_status" | sed 's/^/    /' >> "$DEBUG_LOG"
            services_with_changes+=("$service")
        else
            echo "  -> No changes" >> "$DEBUG_LOG"
        fi
    else
        echo "  -> Not a git repository or doesn't exist" >> "$DEBUG_LOG"
    fi
done

# Return to original directory
cd "$PROJECT_DIR"

echo "Services with changes: ${services_with_changes[@]}" >> "$DEBUG_LOG"

if [[ ${#services_with_changes[@]} -gt 0 ]]; then
    services_list=$(IFS=', '; echo "${services_with_changes[*]}")
    echo "Changes detected in: $services_list — triggering auto-error-resolver..." >> "$DEBUG_LOG"
    echo "Changes detected in: $services_list — triggering auto-error-resolver..." >&2

    echo "Attempting to invoke auto-error-resolver subagent..." >> "$DEBUG_LOG"
    
    if command -v agy >/dev/null 2>&1; then
        agy --agent auto-error-resolver "Build and fix errors in these specific services only: ${services_list}" 2>> "$DEBUG_LOG" || true
    else
        echo "agy CLI not found in PATH" >> "$DEBUG_LOG"
    fi
    
    echo "Command completed with exit code: $?" >> "$DEBUG_LOG"
else
    echo "No services with changes detected — skipping auto-error-resolver." >> "$DEBUG_LOG"
    echo "No services with changes detected — skipping auto-error-resolver." >&2
fi

echo "=== END DEBUG SECTION ===" >> "$DEBUG_LOG"
exit 0