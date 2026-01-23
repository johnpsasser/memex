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
# Memex Auto-Update (check for updates to memex itself)
# Disable with: export MEMEX_UPDATES_DISABLED=TRUE
# -----------------------------------------------------------------------------
MEMEX_SOURCE_FILE="$PROJECT_ROOT/.claude/.memex-source"
if [ -f "$MEMEX_SOURCE_FILE" ] && [ "${MEMEX_UPDATES_DISABLED:-}" != "TRUE" ]; then
    MEMEX_DIR=$(cat "$MEMEX_SOURCE_FILE")

    if [ -d "$MEMEX_DIR/.git" ]; then
        # Save current directory
        ORIG_DIR=$(pwd)
        cd "$MEMEX_DIR"

        # Fetch latest (silent)
        git fetch origin main --quiet 2>/dev/null || true

        # Compare local vs remote
        LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null)
        REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null)

        if [ -n "$LOCAL_HASH" ] && [ -n "$REMOTE_HASH" ] && [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
            # Updates available
            echo ""
            echo "=============================================="
            echo "  MEMEX UPDATE AVAILABLE"
            echo "=============================================="

            # Show what's new (last 3 commits on remote)
            echo "New commits:"
            git log --oneline HEAD..origin/main 2>/dev/null | head -3 | sed 's/^/  /'
            echo ""

            # Attempt to pull and reinstall
            if git pull --ff-only origin main 2>/dev/null; then
                echo "Updating memex..."
                if "$MEMEX_DIR/install.sh" -f "$PROJECT_ROOT" 2>/dev/null; then
                    echo "Memex updated successfully!"
                else
                    echo "Warning: Memex update installed, but reinstall had issues."
                fi
            else
                echo "Note: Memex has local changes. Run manually:"
                echo "  cd $MEMEX_DIR && git pull && ./install.sh -f $PROJECT_ROOT"
            fi
            echo "=============================================="
            echo ""
        fi

        cd "$ORIG_DIR"
    fi
fi

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
