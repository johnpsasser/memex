#!/bin/bash
# =============================================================================
# SessionEnd Hook - Memex Documentation System
# =============================================================================
# Triggered when a Claude Code session ends.
# Archives working documents and cleans up the working directory.
# =============================================================================

set -e

PROJECT_ROOT="{{PROJECT_ROOT}}"
WORKING_DIR="$PROJECT_ROOT/docs/working"
ARCHIVE_DIR="$HOME/.memex/archives"
PROJECT_NAME=$(basename "$PROJECT_ROOT")

# -----------------------------------------------------------------------------
# Telemetry Integration (optional - uses Claude Code's OTel config)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/telemetry.sh" ]]; then
    source "$SCRIPT_DIR/telemetry.sh"
    telemetry_init "session_end"
fi

# -----------------------------------------------------------------------------
# Generate session ID (timestamp-based)
# -----------------------------------------------------------------------------
SESSION_ID="session-$(date +%Y%m%d-%H%M%S)"

# -----------------------------------------------------------------------------
# Check if working directory exists and has content
# -----------------------------------------------------------------------------
if [ ! -d "$WORKING_DIR" ]; then
    # Telemetry: session end with no working dir
    if type emit_session_end &>/dev/null; then
        emit_session_end "$PROJECT_NAME" 0
        telemetry_finish "no_working_dir"
    fi
    exit 0
fi

# Check if directory has any files (excluding .git* files)
FILES=$(ls -A "$WORKING_DIR" 2>/dev/null | grep -v "^\.git")
if [ -z "$FILES" ]; then
    # Telemetry: session end with empty working dir
    if type emit_session_end &>/dev/null; then
        emit_session_end "$PROJECT_NAME" 0
        telemetry_finish "empty_working_dir"
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# Create archive directory if it doesn't exist
# -----------------------------------------------------------------------------
mkdir -p "$ARCHIVE_DIR"

# -----------------------------------------------------------------------------
# Archive working documents
# -----------------------------------------------------------------------------
ARCHIVE_FILE="$ARCHIVE_DIR/${SESSION_ID}.tar.gz"

echo "Archiving working documents..."
echo "  Source: $WORKING_DIR"
echo "  Archive: $ARCHIVE_FILE"

# Create tar archive (excluding .git* files)
cd "$WORKING_DIR"
tar -czf "$ARCHIVE_FILE" --exclude='.*' . 2>/dev/null

if [ $? -eq 0 ]; then
    echo "  Archive created successfully."

    # Count archived files
    FILE_COUNT=$(ls -1 "$WORKING_DIR" 2>/dev/null | grep -v "^\." | wc -l | tr -d ' ')
    echo "  Files archived: $FILE_COUNT"

    # -----------------------------------------------------------------------------
    # Clean up working directory (keep .git* files)
    # -----------------------------------------------------------------------------
    echo "Cleaning up working directory..."
    find "$WORKING_DIR" -type f ! -name ".*" -delete 2>/dev/null
    echo "  Working directory cleaned."
else
    echo "  Warning: Archive creation failed. Working docs preserved."
fi

# -----------------------------------------------------------------------------
# Manage archive retention (keep last 20 archives)
# -----------------------------------------------------------------------------
ARCHIVE_COUNT=$(ls -1 "$ARCHIVE_DIR"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
if [ "$ARCHIVE_COUNT" -gt 20 ]; then
    echo "Managing archive retention..."
    ls -1t "$ARCHIVE_DIR"/*.tar.gz 2>/dev/null | tail -n +21 | xargs rm -f
    REMOVED=$((ARCHIVE_COUNT - 20))
    echo "  Removed $REMOVED old archive(s)."
fi

echo ""
echo "Session cleanup complete."

# Telemetry: emit session end metrics
if type emit_session_end &>/dev/null; then
    emit_session_end "$PROJECT_NAME" "${FILE_COUNT:-0}"
    emit_counter "memex.archive.created" 1 "{\"session.id\":\"$SESSION_ID\"}"
    telemetry_finish "success"
fi

exit 0
