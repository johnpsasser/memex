#!/bin/bash
# =============================================================================
# PostToolUse Hook - Documentation Validation
# =============================================================================
# Triggered after Write or Edit operations on docs/*.md files.
# Reminds to update GLOSSARY.md when documentation is modified.
# Does NOT auto-edit - only provides reminders.
# =============================================================================

PROJECT_ROOT="{{PROJECT_ROOT}}"

# Read the hook input from stdin (JSON format)
INPUT=$(cat)

# Extract tool name and file path using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

# Exit early if jq failed or no file path
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check if the file is in the docs directory
case "$FILE_PATH" in
    */docs/*.md)
        # Continue with validation
        ;;
    *)
        # Not a docs file, exit silently
        exit 0
        ;;
esac

# Skip if this is the GLOSSARY.md itself
if [[ "$FILE_PATH" == *"GLOSSARY.md" ]]; then
    exit 0
fi

GLOSSARY_PATH="$PROJECT_ROOT/docs/GLOSSARY.md"

# Only show reminder if GLOSSARY.md exists
if [ ! -f "$GLOSSARY_PATH" ]; then
    exit 0
fi

# -----------------------------------------------------------------------------
# Reminder about GLOSSARY updates
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  DOCUMENTATION UPDATE REMINDER"
echo "=============================================="
echo ""
echo "File modified: ${FILE_PATH#$PROJECT_ROOT/}"
echo ""

# Extract the relative path for contextual message
REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"

case "$REL_PATH" in
    docs/core/*)
        echo "If you added new system concepts or components,"
        echo "consider adding them to GLOSSARY.md in the appropriate section."
        ;;
    docs/features/*)
        echo "If you added new feature documentation,"
        echo "consider adding keywords to GLOSSARY.md for discoverability."
        ;;
    docs/*)
        echo "If you added new sections or concepts,"
        echo "consider adding relevant keywords to GLOSSARY.md."
        ;;
esac

echo ""
echo "Glossary location: docs/GLOSSARY.md"
echo "=============================================="
echo ""

exit 0
