# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Memex is a context-aware documentation system for Claude Code. It uses Claude Code hooks to automatically inject relevant documentation into conversations based on keywords in user prompts.

## Development

This is a bash-only project. No build step required.

| Task | Command |
|------|---------|
| Install to a project | `./install.sh /path/to/project` |
| Install (force, no prompts) | `./install.sh -f /path/to/project` |
| Install without doc migration | `./install.sh --no-migration /path/to/project` |
| Install with separate worktree | `./install.sh /config/path -w /worktree/path` |

### Testing Hooks Locally

After installing to a project, test hooks manually:

```bash
# Test context-enricher (UserPromptSubmit hook)
echo '{"user_prompt": "tell me about the database schema"}' | .claude/hooks/context-enricher.sh

# Test session-start (SessionStart hook)
.claude/hooks/session-start.sh

# Test validate-docs (PostToolUse hook)
echo '{"tool_name": "Write", "tool_input": {"file_path": "docs/test.md"}}' | .claude/hooks/validate-docs.sh
```

## Architecture

```
memex/
├── install.sh              # Installer (entry point)
├── .claude/
│   ├── hooks/              # Hook scripts (copied to target projects)
│   │   ├── context-enricher.sh   # Core: keyword matching + doc injection
│   │   ├── session-start.sh      # Shows git status, available docs
│   │   ├── session-end.sh        # Archives working documents
│   │   ├── validate-docs.sh      # Size limits, glossary reminders
│   │   ├── scan-docs.sh          # Auto-glossary generator utility
│   │   └── telemetry.sh          # OpenTelemetry helper (sourced by others)
│   └── skills/             # Skills (copied to target projects)
├── skills/                 # Skill source files
│   ├── memex-docs/         # Documentation writing guidelines
│   └── migrate-docs/       # Legacy doc migration helper
└── templates/              # Template files for new installations
    ├── CLAUDE.md.template
    ├── GLOSSARY.md.template
    └── CONTRIBUTING.md.template
```

### Hook Flow

1. **SessionStart** → `session-start.sh`: Checks for memex updates, auto-pulls main branch, shows git status and available docs
2. **UserPromptSubmit** → `context-enricher.sh`: Scans prompt for keywords, injects matching docs with token budget (excludes `docs/archive/`)
3. **PostToolUse** → `validate-docs.sh`: Warns when doc edits exceed size limits
4. **SessionEnd** → `session-end.sh`: Archives `docs/working/` files

### context-enricher.sh Internals

The core logic lives in `context-enricher.sh`:
- Keyword patterns defined via bash `case` statements (lines 178-253, customization section)
- Section-level extraction via `extract_section()` function (lines 274-330)
- Token budget tracking with `~10k` token limit
- Session deduplication via secure temp directory with PPID-based session tokens

To add new keyword mappings, edit the "KEYWORD-TO-DOCUMENTATION MATCHING" section.

## Key Constraints

1. **Bash 3.x compatibility** - No associative arrays (macOS ships bash 3.x)
2. **jq dependency** - Required for JSON parsing in hooks
3. **Token budget** - Default 10k tokens, configurable via `MAX_TOTAL_TOKENS`
4. **Size limits** - Files: 800 lines, Sections: 150 lines
5. **Archive exclusion** - `docs/archive/` is never loaded by context-enricher

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `MEMEX_UPDATES_DISABLED=TRUE` | Disable auto-updates on session start |

## File Naming Conventions

When documentation exceeds limits, split using:
```
CATEGORY_SUBCATEGORY.md
```
Example: `DATABASE_SCHEMA.md`, `DATABASE_QUERIES.md`
