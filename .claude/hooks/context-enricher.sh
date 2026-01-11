#!/bin/bash
# =============================================================================
# UserPromptSubmit Hook - Context Enricher
# =============================================================================
# Analyzes user prompts for documentation-related keywords and injects
# relevant documentation sections into the conversation context.
#
# This is the core of the Memex intelligent auto-loading system.
#
# To customize for your project:
# 1. Add keyword patterns in the "Keyword-to-Documentation Matching" section
# 2. Map keywords to your documentation files
# 3. The hook will auto-inject matched docs wrapped in XML tags
#
# Compatible with bash 3.x (macOS default) - no associative arrays.
# =============================================================================

set -e

PROJECT_ROOT="{{PROJECT_ROOT}}"
DOCS_DIR="$PROJECT_ROOT/docs"

# Read the hook input from stdin (JSON format)
INPUT=$(cat)

# Extract the user prompt using jq
USER_PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null)

# Exit if no prompt or jq not available
if [ -z "$USER_PROMPT" ]; then
    exit 0
fi

# Convert prompt to lowercase for case-insensitive matching
PROMPT_LOWER=$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')

# -----------------------------------------------------------------------------
# Matched docs tracking (space-separated list for bash 3.x compatibility)
# -----------------------------------------------------------------------------
MATCHED_DOCS=""

# Function to add a doc to matched list (deduplicates)
add_doc() {
    local doc="$1"
    case " $MATCHED_DOCS " in
        *" $doc "*)
            # Already in list, skip
            ;;
        *)
            MATCHED_DOCS="$MATCHED_DOCS $doc"
            ;;
    esac
}

# =============================================================================
# KEYWORD-TO-DOCUMENTATION MATCHING
# =============================================================================
# Customize this section for your project!
#
# Pattern: case "$PROMPT_LOWER" in
#            *keyword1*|*keyword2*|*keyword3*)
#                add_doc "path/to/doc.md"
#                ;;
#          esac
#
# The path is relative to your docs/ directory.
# =============================================================================

# Architecture / System design keywords
case "$PROMPT_LOWER" in
    *architecture*|*docker*|*container*|*network*|*infrastructure*|*topology*)
        add_doc "core/ARCHITECTURE.md"
        ;;
esac

# Database keywords
case "$PROMPT_LOWER" in
    *database*|*postgres*|*schema*|*table*|*query*|*sql*|*migration*)
        add_doc "core/DATABASE.md"
        ;;
esac

# API keywords
case "$PROMPT_LOWER" in
    *" api"*|*"api "*|*endpoint*|*route*|*" rest"*|*request*|*response*)
        add_doc "core/API.md"
        ;;
esac

# Deployment / DevOps keywords
case "$PROMPT_LOWER" in
    *deploy*|*"ci/cd"*|*cicd*|*"github action"*|*workflow*|*production*)
        add_doc "DEPLOYMENT.md"
        ;;
esac

# Troubleshooting / Error keywords
case "$PROMPT_LOWER" in
    *troubleshoot*|*" error"*|*"error "*|*debug*|*" fix "*|*issue*|*problem*)
        add_doc "TROUBLESHOOTING.md"
        ;;
esac

# Contributing keywords
case "$PROMPT_LOWER" in
    *contributing*|*contribute*|*guidelines*|*"pull request"*)
        add_doc "CONTRIBUTING.md"
        ;;
esac

# =============================================================================
# Add your own keyword patterns below!
# =============================================================================

# Example: Feature-specific docs
# case "$PROMPT_LOWER" in
#     *authentication*|*login*|*oauth*|*jwt*)
#         add_doc "features/AUTH.md"
#         ;;
# esac

# Example: Testing docs
# case "$PROMPT_LOWER" in
#     *test*|*testing*|*jest*|*vitest*|*coverage*)
#         add_doc "TESTING.md"
#         ;;
# esac

# =============================================================================
# END CUSTOMIZATION SECTION
# =============================================================================

# -----------------------------------------------------------------------------
# Exit if no matches
# -----------------------------------------------------------------------------
MATCHED_DOCS=$(echo "$MATCHED_DOCS" | xargs)  # Trim whitespace
if [ -z "$MATCHED_DOCS" ]; then
    exit 0
fi

# -----------------------------------------------------------------------------
# Output Context Injection
# -----------------------------------------------------------------------------
echo ""
echo "<auto-loaded-documentation>"
echo "<!-- Documentation auto-loaded by Memex based on your query keywords. -->"
echo ""

for doc_file in $MATCHED_DOCS; do
    FULL_PATH="$DOCS_DIR/$doc_file"

    if [ -f "$FULL_PATH" ]; then
        echo "<!-- Source: $doc_file -->"
        echo "<doc path=\"docs/$doc_file\">"

        # Output full content for smaller files, or first 200 lines for larger ones
        LINE_COUNT=$(wc -l < "$FULL_PATH" | tr -d ' ')

        if [ "$LINE_COUNT" -le 500 ]; then
            cat "$FULL_PATH"
        else
            # For large files (>500 lines), extract first 500 lines
            # Note: Docs should be kept under 500 lines for optimal context loading
            head -n 500 "$FULL_PATH"
            echo ""
            echo "<!-- Document truncated at 200 lines. Full content: docs/$doc_file -->"
        fi

        echo "</doc>"
        echo ""
    fi
done

echo "</auto-loaded-documentation>"
echo ""

# Remind about GLOSSARY.md for quick lookups
if [ -f "$DOCS_DIR/GLOSSARY.md" ]; then
    echo "<!-- Tip: For quick keyword lookups, see docs/GLOSSARY.md -->"
    echo ""
fi

exit 0
