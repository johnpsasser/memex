#!/bin/bash
# =============================================================================
# Memex Installer
# =============================================================================
# Sets up the context-aware documentation system for Claude Code.
# Run this script from your project root.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Memex - Documentation Memory System${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Detect project root
# -----------------------------------------------------------------------------
if [ -n "$1" ]; then
    PROJECT_ROOT="$1"
else
    PROJECT_ROOT="$(pwd)"
fi

# Expand to absolute path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

echo -e "Installing to: ${GREEN}$PROJECT_ROOT${NC}"
echo ""

# -----------------------------------------------------------------------------
# Check for existing .claude directory
# -----------------------------------------------------------------------------
if [ -d "$PROJECT_ROOT/.claude" ]; then
    echo -e "${YELLOW}Warning: .claude directory already exists.${NC}"
    read -p "Overwrite hooks? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Get script directory (where memex files are)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Create directory structure
# -----------------------------------------------------------------------------
echo "Creating directories..."
mkdir -p "$PROJECT_ROOT/.claude/hooks"
mkdir -p "$PROJECT_ROOT/docs/core"
mkdir -p "$PROJECT_ROOT/docs/working"

# Add .gitkeep to working directory
touch "$PROJECT_ROOT/docs/working/.gitkeep"

# Add .gitignore for working directory (don't commit temp files)
echo "*" > "$PROJECT_ROOT/docs/working/.gitignore"
echo "!.gitkeep" >> "$PROJECT_ROOT/docs/working/.gitignore"
echo "!.gitignore" >> "$PROJECT_ROOT/docs/working/.gitignore"

# -----------------------------------------------------------------------------
# Copy and configure hooks
# -----------------------------------------------------------------------------
echo "Installing hooks..."

# Copy each hook and update PROJECT_ROOT
for hook in session-start.sh session-end.sh context-enricher.sh validate-docs.sh; do
    if [ -f "$SCRIPT_DIR/.claude/hooks/$hook" ]; then
        # Copy the hook
        cp "$SCRIPT_DIR/.claude/hooks/$hook" "$PROJECT_ROOT/.claude/hooks/$hook"

        # Update PROJECT_ROOT variable in the hook
        sed -i.bak "s|^PROJECT_ROOT=.*|PROJECT_ROOT=\"$PROJECT_ROOT\"|" "$PROJECT_ROOT/.claude/hooks/$hook"
        rm -f "$PROJECT_ROOT/.claude/hooks/$hook.bak"

        # Make executable
        chmod +x "$PROJECT_ROOT/.claude/hooks/$hook"

        echo -e "  ${GREEN}+${NC} $hook"
    fi
done

# Copy telemetry helper (sourced by other hooks, not a standalone hook)
if [ -f "$SCRIPT_DIR/.claude/hooks/telemetry.sh" ]; then
    cp "$SCRIPT_DIR/.claude/hooks/telemetry.sh" "$PROJECT_ROOT/.claude/hooks/telemetry.sh"
    chmod +x "$PROJECT_ROOT/.claude/hooks/telemetry.sh"
    echo -e "  ${GREEN}+${NC} telemetry.sh (helper)"
fi

# -----------------------------------------------------------------------------
# Copy skills
# -----------------------------------------------------------------------------
echo "Installing skills..."

if [ -d "$SCRIPT_DIR/.claude/skills" ]; then
    # Copy each skill directory
    for skill_dir in "$SCRIPT_DIR/.claude/skills"/*/; do
        if [ -d "$skill_dir" ]; then
            skill_name=$(basename "$skill_dir")
            mkdir -p "$PROJECT_ROOT/.claude/skills/$skill_name"
            cp -r "$skill_dir"* "$PROJECT_ROOT/.claude/skills/$skill_name/" 2>/dev/null || true
            echo -e "  ${GREEN}+${NC} $skill_name"
        fi
    done
else
    echo -e "  ${YELLOW}~${NC} No skills to install"
fi

# -----------------------------------------------------------------------------
# Create settings.json with correct paths
# -----------------------------------------------------------------------------
echo "Creating settings.json..."

cat > "$PROJECT_ROOT/.claude/settings.json" << EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_ROOT/.claude/hooks/session-start.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_ROOT/.claude/hooks/session-end.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_ROOT/.claude/hooks/context-enricher.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_ROOT/.claude/hooks/validate-docs.sh"
          }
        ]
      }
    ]
  }
}
EOF

echo -e "  ${GREEN}+${NC} settings.json"

# -----------------------------------------------------------------------------
# Copy documentation templates
# -----------------------------------------------------------------------------
echo "Creating documentation templates..."

# CLAUDE.md
if [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]; then
    if [ -f "$SCRIPT_DIR/templates/CLAUDE.md.template" ]; then
        PROJECT_NAME=$(basename "$PROJECT_ROOT")
        sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$SCRIPT_DIR/templates/CLAUDE.md.template" > "$PROJECT_ROOT/CLAUDE.md"
        echo -e "  ${GREEN}+${NC} CLAUDE.md"
    fi
else
    echo -e "  ${YELLOW}~${NC} CLAUDE.md (already exists, skipped)"
fi

# GLOSSARY.md
if [ ! -f "$PROJECT_ROOT/docs/GLOSSARY.md" ]; then
    if [ -f "$SCRIPT_DIR/templates/GLOSSARY.md.template" ]; then
        PROJECT_NAME=$(basename "$PROJECT_ROOT")
        sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$SCRIPT_DIR/templates/GLOSSARY.md.template" > "$PROJECT_ROOT/docs/GLOSSARY.md"
        echo -e "  ${GREEN}+${NC} docs/GLOSSARY.md"
    fi
else
    echo -e "  ${YELLOW}~${NC} docs/GLOSSARY.md (already exists, skipped)"
fi

# CONTRIBUTING.md
if [ ! -f "$PROJECT_ROOT/docs/CONTRIBUTING.md" ]; then
    if [ -f "$SCRIPT_DIR/templates/CONTRIBUTING.md.template" ]; then
        PROJECT_NAME=$(basename "$PROJECT_ROOT")
        sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$SCRIPT_DIR/templates/CONTRIBUTING.md.template" > "$PROJECT_ROOT/docs/CONTRIBUTING.md"
        echo -e "  ${GREEN}+${NC} docs/CONTRIBUTING.md"
    fi
else
    echo -e "  ${YELLOW}~${NC} docs/CONTRIBUTING.md (already exists, skipped)"
fi

# -----------------------------------------------------------------------------
# Check for jq dependency
# -----------------------------------------------------------------------------
echo ""
echo "Checking dependencies..."
if command -v jq &> /dev/null; then
    echo -e "  ${GREEN}+${NC} jq found"
else
    echo -e "  ${YELLOW}!${NC} jq not found - install it for full functionality"
    echo "    macOS: brew install jq"
    echo "    Ubuntu: apt-get install jq"
fi

# -----------------------------------------------------------------------------
# Success message
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Customize your documentation:"
echo "   - Edit CLAUDE.md with your project's key info"
echo "   - Edit docs/GLOSSARY.md with your keywords"
echo "   - Add docs to docs/core/, docs/features/, etc."
echo ""
echo "2. Customize the context-enricher hook:"
echo "   - Edit .claude/hooks/context-enricher.sh"
echo "   - Add keyword patterns for your docs"
echo ""
echo "3. Start a Claude Code session to test:"
echo "   - Session start hook will show git info"
echo "   - Try asking about 'architecture' or 'database'"
echo "   - Relevant docs will auto-inject into context"
echo ""
echo -e "Docs: ${BLUE}https://github.com/johnpsasser/memex${NC}"
echo ""
