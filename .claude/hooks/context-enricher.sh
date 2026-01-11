#!/bin/bash
# =============================================================================
# UserPromptSubmit Hook - Context Enricher
# =============================================================================
# Analyzes user prompts for documentation-related keywords and injects
# relevant documentation sections into the conversation context.
#
# This is the core of the Memex intelligent auto-loading system.
#
# Features:
# - Section-level loading (extracts specific sections via anchors)
# - Context budget awareness (stops at token threshold)
# - Session-level deduplication (tracks loaded docs)
# - Smart truncation (800 lines max for files, 150 for sections)
#
# To customize for your project:
# 1. Add keyword patterns in the "Keyword-to-Documentation Matching" section
# 2. Map keywords to your documentation files (supports anchors: file.md#section)
# 3. The hook will auto-inject matched docs wrapped in XML tags
#
# Compatible with bash 3.x (macOS default) - no associative arrays.
# =============================================================================

set -e

PROJECT_ROOT="{{PROJECT_ROOT}}"
DOCS_DIR="$PROJECT_ROOT/docs"

# -----------------------------------------------------------------------------
# Telemetry Integration (optional - uses Claude Code's OTel config)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/telemetry.sh" ]]; then
    source "$SCRIPT_DIR/telemetry.sh"
    telemetry_init "user_prompt_submit"
fi

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
MAX_FILE_LINES=800           # Maximum lines to load from a single file
MAX_SECTION_LINES=150        # Maximum lines to load from a section
MAX_TOTAL_TOKENS=10000       # Approximate token budget (~7 tokens per line)
TOKENS_PER_LINE=7            # Rough estimate for markdown

# Session cache for deduplication (unique per terminal session)
SESSION_CACHE_DIR="/tmp/memex-session-$$"
LOADED_DOCS_FILE="$SESSION_CACHE_DIR/loaded_docs"

# Initialize session cache directory
mkdir -p "$SESSION_CACHE_DIR" 2>/dev/null || true

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
# Token tracking
# -----------------------------------------------------------------------------
TOTAL_TOKENS_LOADED=0

# Check if we've exceeded our token budget
check_budget() {
    if [ "$TOTAL_TOKENS_LOADED" -ge "$MAX_TOTAL_TOKENS" ]; then
        return 1  # Budget exceeded
    fi
    return 0  # Budget available
}

# Add tokens to our running total
add_tokens() {
    local lines=$1
    local tokens=$((lines * TOKENS_PER_LINE))
    TOTAL_TOKENS_LOADED=$((TOTAL_TOKENS_LOADED + tokens))
}

# -----------------------------------------------------------------------------
# Session deduplication
# -----------------------------------------------------------------------------
# Check if a doc (with optional section) was already loaded this session
is_already_loaded() {
    local doc_ref="$1"
    if [ -f "$LOADED_DOCS_FILE" ]; then
        grep -q "^${doc_ref}$" "$LOADED_DOCS_FILE" 2>/dev/null && return 0
    fi
    return 1
}

# Mark a doc as loaded in this session
mark_as_loaded() {
    local doc_ref="$1"
    echo "$doc_ref" >> "$LOADED_DOCS_FILE"
}

# -----------------------------------------------------------------------------
# Matched docs tracking (space-separated list for bash 3.x compatibility)
# -----------------------------------------------------------------------------
MATCHED_DOCS=""

# Function to add a doc to matched list (deduplicates within this request)
add_doc() {
    local doc="$1"

    # Skip if already in this request's list
    case " $MATCHED_DOCS " in
        *" $doc "*)
            return
            ;;
    esac

    # Skip if already loaded in this session
    if is_already_loaded "$doc"; then
        # Telemetry: track cache hit (deduplication)
        if type emit_cache_hit &>/dev/null; then
            emit_cache_hit "$doc"
        fi
        return
    fi

    MATCHED_DOCS="$MATCHED_DOCS $doc"
}

# =============================================================================
# KEYWORD-TO-DOCUMENTATION MATCHING
# =============================================================================
# Customize this section for your project!
#
# Pattern: case "$PROMPT_LOWER" in
#            *keyword1*|*keyword2*|*keyword3*)
#                add_doc "path/to/doc.md"           # Full file
#                add_doc "path/to/doc.md#section"   # Specific section
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

# Example: Feature-specific docs with section loading
# case "$PROMPT_LOWER" in
#     *authentication*|*login*|*oauth*)
#         add_doc "features/AUTH.md#oauth-flow"  # Section-level loading
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
    # Telemetry: no keywords matched
    if type emit_no_match &>/dev/null; then
        emit_no_match
        telemetry_finish "no_match"
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# Section Extraction Function
# -----------------------------------------------------------------------------
# Extracts a specific section from a markdown file based on anchor
# Usage: extract_section "file.md" "section-name"
extract_section() {
    local file="$1"
    local section="$2"
    local in_section=0
    local section_level=0
    local line_count=0
    local output=""

    # Convert anchor to header pattern (e.g., "quick-start" -> "Quick Start" or similar)
    local section_pattern=$(echo "$section" | tr '-' ' ')

    while IFS= read -r line; do
        # Check if this is a header line
        if [[ "$line" =~ ^(#+)[[:space:]]+(.*) ]]; then
            local hashes="${BASH_REMATCH[1]}"
            local header_text="${BASH_REMATCH[2]}"
            local current_level=${#hashes}

            # Slugify the header for comparison
            local header_slug=$(echo "$header_text" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')

            if [ "$in_section" -eq 0 ]; then
                # Check if this header matches our target section
                if [[ "$header_slug" == *"$section"* ]] || [[ "$(echo "$header_text" | tr '[:upper:]' '[:lower:]')" == *"$section_pattern"* ]]; then
                    in_section=1
                    section_level=$current_level
                    output="$line"$'\n'
                    line_count=1
                fi
            else
                # We're in the section - check if we've hit a same-level or higher header
                if [ "$current_level" -le "$section_level" ]; then
                    break  # End of our section
                fi
                output="$output$line"$'\n'
                line_count=$((line_count + 1))
            fi
        elif [ "$in_section" -eq 1 ]; then
            output="$output$line"$'\n'
            line_count=$((line_count + 1))
        fi

        # Enforce section line limit
        if [ "$line_count" -ge "$MAX_SECTION_LINES" ]; then
            output="$output"$'\n'"<!-- Section truncated at $MAX_SECTION_LINES lines -->"
            break
        fi
    done < "$file"

    if [ "$in_section" -eq 1 ]; then
        echo "$output"
        echo "$line_count"  # Return line count as last line
    else
        echo ""
        echo "0"
    fi
}

# -----------------------------------------------------------------------------
# Output Context Injection
# -----------------------------------------------------------------------------
echo ""
echo "<auto-loaded-documentation>"
echo "<!-- Documentation auto-loaded by Memex based on your query keywords. -->"
echo "<!-- Token budget: ~$MAX_TOTAL_TOKENS tokens | Session deduplication active -->"
echo ""

DOCS_LOADED=0

for doc_ref in $MATCHED_DOCS; do
    # Check token budget before loading more
    if ! check_budget; then
        echo "<!-- Token budget reached (~$TOTAL_TOKENS_LOADED tokens). Skipping remaining docs. -->"
        break
    fi

    # Parse file path and optional section
    if [[ "$doc_ref" == *"#"* ]]; then
        doc_file="${doc_ref%%#*}"
        section="${doc_ref##*#}"
    else
        doc_file="$doc_ref"
        section=""
    fi

    FULL_PATH="$DOCS_DIR/$doc_file"

    if [ -f "$FULL_PATH" ]; then
        DOCS_LOADED=$((DOCS_LOADED + 1))

        if [ -n "$section" ]; then
            # Section-level loading
            echo "<!-- Source: $doc_file#$section -->"
            echo "<doc path=\"docs/$doc_ref\">"

            # Extract the section
            section_output=$(extract_section "$FULL_PATH" "$section")
            section_lines=$(echo "$section_output" | tail -1)
            section_content=$(echo "$section_output" | head -n -1)

            if [ "$section_lines" -gt 0 ]; then
                echo "$section_content"
                add_tokens "$section_lines"
            else
                # Section not found, fall back to full file (truncated)
                echo "<!-- Section '$section' not found, loading file summary -->"
                head -n "$MAX_SECTION_LINES" "$FULL_PATH"
                add_tokens "$MAX_SECTION_LINES"
            fi

            echo "</doc>"
        else
            # Full file loading (with truncation)
            echo "<!-- Source: $doc_file -->"
            echo "<doc path=\"docs/$doc_file\">"

            LINE_COUNT=$(wc -l < "$FULL_PATH" | tr -d ' ')

            if [ "$LINE_COUNT" -le "$MAX_FILE_LINES" ]; then
                cat "$FULL_PATH"
                add_tokens "$LINE_COUNT"
            else
                head -n "$MAX_FILE_LINES" "$FULL_PATH"
                echo ""
                echo "<!-- Document truncated at $MAX_FILE_LINES lines. Full content: docs/$doc_file -->"
                add_tokens "$MAX_FILE_LINES"
            fi

            echo "</doc>"
        fi

        # Mark as loaded for session deduplication
        mark_as_loaded "$doc_ref"

        # Telemetry: track cache miss (doc loaded)
        if type emit_cache_miss &>/dev/null; then
            emit_cache_miss "$doc_ref"
        fi

        echo ""
    fi
done

echo "</auto-loaded-documentation>"
echo ""
echo "<!-- Loaded $DOCS_LOADED docs (~$TOTAL_TOKENS_LOADED tokens). For keyword lookups, see docs/GLOSSARY.md -->"
echo ""

# -----------------------------------------------------------------------------
# Telemetry: Emit final metrics
# -----------------------------------------------------------------------------
if type emit_docs_loaded &>/dev/null; then
    emit_docs_loaded "$DOCS_LOADED"
    emit_tokens_injected "$TOTAL_TOKENS_LOADED"
    emit_budget_status "$TOTAL_TOKENS_LOADED" "$MAX_TOTAL_TOKENS"
    telemetry_finish "success"
fi

exit 0
