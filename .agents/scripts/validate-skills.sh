#!/bin/bash
# validate-skills.sh - Quality and structure audit for .agents/skills/
# Checks:
#   1. Every skill directory contains SKILL.md
#   2. YAML frontmatter contains name and description
#   3. Progressive disclosure: SKILL.md ≤ 500 lines
#   4. Registered in .agents/skills/skill-rules.json

set -u

PROJECT_DIR="${AGY_PROJECT_DIR:-$(pwd)}"
SKILLS_DIR="$PROJECT_DIR/.agents/skills"
RULES_FILE="$SKILLS_DIR/skill-rules.json"

echo "Validating skills in $SKILLS_DIR..."
echo

errors=0
warnings=0

for dir in "$SKILLS_DIR"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    skill_file="$dir/SKILL.md"

    if [ ! -f "$skill_file" ]; then
        echo "  [FAIL] $name: missing SKILL.md"
        errors=$((errors + 1))
        continue
    fi

    # Check frontmatter
    has_name=$(grep -E '^name:[[:space:]]*' "$skill_file" || true)
    has_desc=$(grep -E '^description:[[:space:]]*' "$skill_file" || true)
    if [ -z "$has_name" ] || [ -z "$has_desc" ]; then
        echo "  [FAIL] $name/SKILL.md: missing required YAML frontmatter (name or description)"
        errors=$((errors + 1))
    fi

    # Check 500-line progressive disclosure rule
    lines=$(wc -l < "$skill_file" | tr -d ' ')
    if [ "$lines" -gt 500 ]; then
        echo "  [WARN] $name/SKILL.md is $lines lines (>500 lines) - consider moving reference material to resources/ or references/"
        warnings=$((warnings + 1))
    fi

    # Check registration in skill-rules.json
    if [ -f "$RULES_FILE" ]; then
        registered=$(grep "\"$name\":" "$RULES_FILE" || true)
        if [ -z "$registered" ]; then
            echo "  [WARN] $name: not registered in skill-rules.json"
            warnings=$((warnings + 1))
        fi
    fi

    echo "  [PASS] $name ($lines lines)"
done

echo
echo "Validation complete: $errors error(s), $warnings warning(s)."
if [ "$errors" -gt 0 ]; then
    exit 1
fi
exit 0
