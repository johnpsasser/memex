#!/bin/bash
# =============================================================================
# SessionStart Hook - Memex Documentation System
# =============================================================================
# Triggered when a new Claude Code session begins.
# Shows current repo state and reminds about documentation auto-loading.
# =============================================================================

set -e

PROJECT_ROOT="{{PROJECT_ROOT}}"
cd "$PROJECT_ROOT"

PROJECT_NAME=$(basename "$PROJECT_ROOT")

# -----------------------------------------------------------------------------
# Auto-pull latest changes (conservative approach)
# Only pulls on main/master, only if working tree is clean, ff-only
# -----------------------------------------------------------------------------
if [ -d ".git" ]; then
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
    if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
        # Check if working tree is clean (no staged or unstaged changes)
        if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
            # Attempt fast-forward only pull (fails safely if diverged)
            if git pull --ff-only origin "$CURRENT_BRANCH" 2>/dev/null; then
                echo "Pulled latest changes from origin/$CURRENT_BRANCH"
            fi
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Telemetry Integration (optional - uses Claude Code's OTel config)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/telemetry.sh" ]]; then
    source "$SCRIPT_DIR/telemetry.sh"
    telemetry_init "session_start"
    emit_session_start "$PROJECT_NAME"
fi

echo "=============================================="
echo "  $PROJECT_NAME SESSION INITIALIZED"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Git Branch Information
# -----------------------------------------------------------------------------
if [ -d ".git" ]; then
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "Git Branch: $CURRENT_BRANCH"
    echo ""

    # -----------------------------------------------------------------------------
    # Recent Commits (last 5)
    # -----------------------------------------------------------------------------
    echo "Recent Commits:"
    echo "---------------"
    git log --oneline -5 2>/dev/null || echo "  (no commits found)"
    echo ""

    # -----------------------------------------------------------------------------
    # Changed Files (staged and unstaged)
    # -----------------------------------------------------------------------------
    echo "Changed Files:"
    echo "--------------"
    STAGED=$(git diff --cached --name-only 2>/dev/null)
    UNSTAGED=$(git diff --name-only 2>/dev/null)
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null)

    if [ -n "$STAGED" ]; then
        echo "  Staged:"
        echo "$STAGED" | sed 's/^/    /'
    fi

    if [ -n "$UNSTAGED" ]; then
        echo "  Modified:"
        echo "$UNSTAGED" | sed 's/^/    /'
    fi

    if [ -n "$UNTRACKED" ]; then
        echo "  Untracked:"
        echo "$UNTRACKED" | head -10 | sed 's/^/    /'
        UNTRACKED_COUNT=$(echo "$UNTRACKED" | wc -l | tr -d ' ')
        if [ "$UNTRACKED_COUNT" -gt 10 ]; then
            echo "    ... and $((UNTRACKED_COUNT - 10)) more"
        fi
    fi

    if [ -z "$STAGED" ] && [ -z "$UNSTAGED" ] && [ -z "$UNTRACKED" ]; then
        echo "  (working tree clean)"
    fi
    echo ""
fi

# -----------------------------------------------------------------------------
# Documentation Reminder
# -----------------------------------------------------------------------------
echo "Documentation System:"
echo "--------------------"
echo "  Auto-loading enabled for context-aware documentation."
echo "  Keywords in your prompts trigger relevant doc injection."
echo ""

# List available docs
if [ -d "$PROJECT_ROOT/docs" ]; then
    echo "  Available docs:"
    find "$PROJECT_ROOT/docs" -name "*.md" -type f 2>/dev/null | head -10 | while read -r doc; do
        echo "    - ${doc#$PROJECT_ROOT/}"
    done
    DOC_COUNT=$(find "$PROJECT_ROOT/docs" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DOC_COUNT" -gt 10 ]; then
        echo "    ... and $((DOC_COUNT - 10)) more"
    fi
    echo ""
fi

# -----------------------------------------------------------------------------
# Working Documents Status
# -----------------------------------------------------------------------------
WORKING_DIR="$PROJECT_ROOT/docs/working"
if [ -d "$WORKING_DIR" ]; then
    FILES=$(ls -A "$WORKING_DIR" 2>/dev/null | grep -v "^\.git" | head -5)
    if [ -n "$FILES" ]; then
        echo "Working Documents:"
        echo "-----------------"
        ls -la "$WORKING_DIR" | grep -v "^total" | grep -v "^\." | head -5 | sed 's/^/  /'
        echo ""
    fi
fi

echo "=============================================="
echo ""

# Telemetry: finalize
if type telemetry_finish &>/dev/null; then
    telemetry_finish "success"
fi

exit 0
