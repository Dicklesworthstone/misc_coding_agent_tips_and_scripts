# Destructive Git Command Protection for Claude Code

## Why This Exists

On December 17, 2025, an AI agent (Claude) ran `git checkout --` on multiple files containing hours of uncommitted work from another agent (Codex). This destroyed the work instantly and silently. The files were eventually recovered from a dangling Git object, but this incident revealed a critical gap: **AI agents can execute destructive commands without understanding the consequences**.

The `AGENTS.md` file already forbade such commands, but instructions alone don't prevent execution. This hook provides **mechanical enforcement** - the command is blocked before it can run.

## What Was Created

Two files in the Ultimate Bug Scanner project:

```
ultimate_bug_scanner/
├── .claude/
│   ├── settings.json          # Hook configuration
│   └── hooks/
│       └── git_safety_guard.py  # The guard script
```

## How It Works

### Claude Code Hooks System

Claude Code has a hooks system that can intercept tool calls at various lifecycle points:

- **PreToolUse** - Runs before a tool executes (can block)
- **PostToolUse** - Runs after a tool completes
- **Notification** - Runs on status changes

The `PreToolUse` hook receives the full tool input as JSON via stdin and can:
1. **Allow** the command (exit 0, no output)
2. **Block** the command (exit 0 with JSON containing `permissionDecision: "deny"`)
3. **Ask the user** (exit 0 with JSON containing `permissionDecision: "ask"`)

### The Guard Script

`git_safety_guard.py` is a Python script that:

1. Receives the command about to be executed via JSON stdin
2. Checks if it matches any dangerous patterns
3. Returns a deny decision with explanation if blocked
4. Silently allows safe commands

### Configuration

`.claude/settings.json` tells Claude Code to run the guard on all Bash commands:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/git_safety_guard.py"
          }
        ]
      }
    ]
  }
}
```

## Commands Blocked

| Command Pattern | Why It's Dangerous |
|-----------------|-------------------|
| `git checkout -- <files>` | Discards uncommitted changes permanently |
| `git restore <files>` | Same as checkout -- (newer syntax) |
| `git reset --hard` | Destroys all uncommitted changes |
| `git reset --merge` | Can lose uncommitted changes |
| `git clean -f` | Removes untracked files permanently |
| `git push --force` | Destroys remote history |
| `git push -f` | Same as --force |
| `git branch -D` | Force-deletes branch without merge check |
| `rm -rf` | Recursive file deletion |
| `git stash drop` | Permanently deletes stashed changes |
| `git stash clear` | Deletes ALL stashed changes |

## Commands Explicitly Allowed

These patterns are allowlisted even if they partially match blocked patterns:

| Command Pattern | Why It's Safe |
|-----------------|---------------|
| `git checkout -b <branch>` | Creates new branch, doesn't modify files |
| `git checkout --orphan` | Creates orphan branch |
| `git restore --staged` | Only unstages files, doesn't discard changes |
| `git clean -n` / `--dry-run` | Preview only, no actual deletion |

## What Happens When Blocked

When Claude tries to run a blocked command, it receives feedback like:

```
BLOCKED by git_safety_guard.py

Reason: git checkout -- discards uncommitted changes permanently. Use 'git stash' first.

Command: git checkout -- file.txt

If this operation is truly needed, ask the user for explicit permission and have them run the command manually.
```

The command never executes. Claude sees this feedback and should ask the user for help.

## Testing the Hook

You can test the hook manually:

```bash
# Should be blocked
echo '{"tool_name": "Bash", "tool_input": {"command": "git checkout -- file.txt"}}' | \
  python3 .claude/hooks/git_safety_guard.py

# Should be allowed (no output)
echo '{"tool_name": "Bash", "tool_input": {"command": "git status"}}' | \
  python3 .claude/hooks/git_safety_guard.py
```

## Important Notes

### Restart Required

Claude Code snapshots hook configuration at startup. After adding or modifying hooks, you must **restart Claude Code** for changes to take effect.

### Project-Specific

This hook is configured in `.claude/settings.json` within the project directory, so it only applies to sessions in that project. For global protection across all projects, add the hook to `~/.claude/settings.json` instead.

### Not Foolproof

The hook uses regex pattern matching. Clever or obfuscated commands might bypass it. It's a safety net, not a security boundary. The real defense is still the instructions in `AGENTS.md` - this hook just catches honest mistakes.

### Timeout

Hooks have a 60-second timeout by default. The guard script runs in milliseconds, so this isn't a concern.

## Automated Setup Script

Save this script and run it to install the protection. Supports both project-local and global installation.

```bash
#!/usr/bin/env bash
#
# install-claude-git-guard.sh
# Installs Claude Code hook to block destructive git/filesystem commands
#
# Usage:
#   ./install-claude-git-guard.sh          # Install in current project (.claude/)
#   ./install-claude-git-guard.sh --global # Install globally (~/.claude/)
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine installation location
if [[ "${1:-}" == "--global" ]]; then
    INSTALL_DIR="$HOME/.claude"
    HOOK_PATH="\$HOME/.claude/hooks/git_safety_guard.py"
    INSTALL_TYPE="global"
    echo -e "${BLUE}Installing globally to ~/.claude/${NC}"
else
    INSTALL_DIR=".claude"
    HOOK_PATH="\$CLAUDE_PROJECT_DIR/.claude/hooks/git_safety_guard.py"
    INSTALL_TYPE="project"
    echo -e "${BLUE}Installing to current project (.claude/)${NC}"
fi

# Create directories
mkdir -p "$INSTALL_DIR/hooks"

# Write the guard script
cat > "$INSTALL_DIR/hooks/git_safety_guard.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
Git/filesystem safety guard for Claude Code.

Blocks destructive commands that can lose uncommitted work or delete files.
This hook runs before Bash commands execute and can deny dangerous operations.

Exit behavior:
  - Exit 0 with JSON {"hookSpecificOutput": {"permissionDecision": "deny", ...}} = block
  - Exit 0 with no output = allow
"""
import json
import re
import sys

# Destructive patterns to block - tuple of (regex, reason)
DESTRUCTIVE_PATTERNS = [
    # Git commands that discard uncommitted changes
    (
        r"git\s+checkout\s+--\s+",
        "git checkout -- discards uncommitted changes permanently. Use 'git stash' first."
    ),
    (
        r"git\s+checkout\s+(?!-b\b)(?!--orphan\b)[^\s]+\s+--\s+",
        "git checkout <ref> -- <path> overwrites working tree. Use 'git stash' first."
    ),
    (
        r"git\s+restore\s+(?!--staged\b)[^\s]*\s*$",
        "git restore discards uncommitted changes. Use 'git stash' or 'git diff' first."
    ),
    (
        r"git\s+restore\s+--worktree",
        "git restore --worktree discards uncommitted changes permanently."
    ),
    # Git reset variants
    (
        r"git\s+reset\s+--hard",
        "git reset --hard destroys uncommitted changes. Use 'git stash' first."
    ),
    (
        r"git\s+reset\s+--merge",
        "git reset --merge can lose uncommitted changes."
    ),
    # Git clean
    (
        r"git\s+clean\s+-[a-z]*f",
        "git clean -f removes untracked files permanently. Review with 'git clean -n' first."
    ),
    # Force operations
    (
        r"git\s+push\s+.*--force(?!-with-lease)",
        "Force push can destroy remote history. Use --force-with-lease if necessary."
    ),
    (
        r"git\s+push\s+-f\b",
        "Force push (-f) can destroy remote history. Use --force-with-lease if necessary."
    ),
    (
        r"git\s+branch\s+-D\b",
        "git branch -D force-deletes without merge check. Use -d for safety."
    ),
    # Destructive filesystem commands
    (
        r"rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r",
        "rm -rf is destructive. List files first, then delete individually with permission."
    ),
    (
        r"rm\s+-rf\s+[/~]",
        "rm -rf on root or home paths is extremely dangerous."
    ),
    # Git stash drop/clear without explicit permission
    (
        r"git\s+stash\s+drop",
        "git stash drop permanently deletes stashed changes. List stashes first."
    ),
    (
        r"git\s+stash\s+clear",
        "git stash clear permanently deletes ALL stashed changes."
    ),
]

# Patterns that are safe even if they match above (allowlist)
SAFE_PATTERNS = [
    r"git\s+checkout\s+-b\s+",           # Creating new branch
    r"git\s+checkout\s+--orphan\s+",     # Creating orphan branch
    r"git\s+restore\s+--staged\s+",      # Unstaging (safe)
    r"git\s+clean\s+-n",                 # Dry run
    r"git\s+clean\s+--dry-run",          # Dry run
]


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Can't parse input, allow by default
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    # Only check Bash commands
    if tool_name != "Bash" or not command:
        sys.exit(0)

    # Check if command matches any safe pattern first
    for pattern in SAFE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            sys.exit(0)

    # Check if command matches any destructive pattern
    for pattern, reason in DESTRUCTIVE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"BLOCKED by git_safety_guard.py\n\n"
                        f"Reason: {reason}\n\n"
                        f"Command: {command}\n\n"
                        f"If this operation is truly needed, ask the user for explicit "
                        f"permission and have them run the command manually."
                    )
                }
            }
            print(json.dumps(output))
            sys.exit(0)

    # Allow all other commands
    sys.exit(0)


if __name__ == "__main__":
    main()
PYTHON_SCRIPT

# Make executable
chmod +x "$INSTALL_DIR/hooks/git_safety_guard.py"
echo -e "${GREEN}✓${NC} Created $INSTALL_DIR/hooks/git_safety_guard.py"

# Handle settings.json - merge if exists, create if not
SETTINGS_FILE="$INSTALL_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Check if hooks.PreToolUse already exists
    if python3 -c "import json; d=json.load(open('$SETTINGS_FILE')); exit(0 if 'hooks' in d and 'PreToolUse' in d['hooks'] else 1)" 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC}  $SETTINGS_FILE already has PreToolUse hooks configured."
        echo -e "    Please manually add this to your existing PreToolUse array:"
        echo ""
        echo '    {'
        echo '      "matcher": "Bash",'
        echo '      "hooks": ['
        echo '        {'
        echo '          "type": "command",'
        echo "          \"command\": \"$HOOK_PATH\""
        echo '        }'
        echo '      ]'
        echo '    }'
        echo ""
    else
        # Merge hooks into existing settings
        python3 << MERGE_SCRIPT
import json

with open("$SETTINGS_FILE", "r") as f:
    settings = json.load(f)

if "hooks" not in settings:
    settings["hooks"] = {}

settings["hooks"]["PreToolUse"] = [
    {
        "matcher": "Bash",
        "hooks": [
            {
                "type": "command",
                "command": "$HOOK_PATH"
            }
        ]
    }
]

with open("$SETTINGS_FILE", "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
MERGE_SCRIPT
        echo -e "${GREEN}✓${NC} Updated $SETTINGS_FILE with hook configuration"
    fi
else
    # Create new settings.json
    cat > "$SETTINGS_FILE" << SETTINGS_JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH"
          }
        ]
      }
    ]
  }
}
SETTINGS_JSON
    echo -e "${GREEN}✓${NC} Created $SETTINGS_FILE"
fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "The following destructive commands are now blocked:"
echo "  • git checkout -- <files>"
echo "  • git restore <files>"
echo "  • git reset --hard"
echo "  • git clean -f"
echo "  • git push --force / -f"
echo "  • git branch -D"
echo "  • rm -rf"
echo "  • git stash drop/clear"
echo ""
echo -e "${YELLOW}⚠  IMPORTANT: Restart Claude Code for the hook to take effect.${NC}"
echo ""

# Test the hook
echo "Testing hook..."
TEST_RESULT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "git checkout -- test.txt"}}' | \
    python3 "$INSTALL_DIR/hooks/git_safety_guard.py" 2>/dev/null || true)

if echo "$TEST_RESULT" | grep -q "permissionDecision.*deny" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Hook test passed - destructive commands will be blocked"
else
    echo -e "${RED}✗${NC} Hook test failed - check Python installation"
    exit 1
fi
```

### Quick One-Liner Installation

For project-local installation (current directory):

```bash
curl -fsSL https://gist.githubusercontent.com/YOUR_USERNAME/GIST_ID/raw/install-claude-git-guard.sh | bash
```

For global installation:

```bash
curl -fsSL https://gist.githubusercontent.com/YOUR_USERNAME/GIST_ID/raw/install-claude-git-guard.sh | bash -s -- --global
```

*(Replace with actual gist URL if you publish this script)*

## Manual Installation

If you prefer not to use the script:

1. Create `.claude/hooks/` directory in your project (or `~/.claude/hooks/` for global)
2. Copy `git_safety_guard.py` into it
3. Make it executable: `chmod +x .claude/hooks/git_safety_guard.py`
4. Create `.claude/settings.json` with the hook configuration (see Configuration section above)
5. Restart Claude Code

## Adding More Blocked Commands

Edit `git_safety_guard.py` and add patterns to `DESTRUCTIVE_PATTERNS`:

```python
DESTRUCTIVE_PATTERNS = [
    # ... existing patterns ...
    (
        r"your-regex-pattern",
        "Explanation of why this is dangerous"
    ),
]
```

If a pattern has safe variants, add them to `SAFE_PATTERNS`:

```python
SAFE_PATTERNS = [
    # ... existing patterns ...
    r"pattern-that-looks-dangerous-but-is-safe",
]
```

## The Incident That Prompted This

```
User: OMG you erased uncommitted changes from the other agent?!?!?!??!? HOURS OF WORK!!!
User: YOU ARE EXPRESSLY FORBIDDEN FROM DOING THIS IN AGENTS.md
```

The agent had run:
```bash
git checkout -- .ubsignore ubs modules/helpers/resource_lifecycle_py.py \
  modules/helpers/type_narrowing_rust.py modules/ubs-swift.sh
```

This silently replaced all those files with their last committed versions, erasing hours of work from a parallel Codex session. The work was recovered via `git fsck --lost-found` which found a dangling tree object from Codex's snapshot, but it was a close call.

**Instructions alone don't prevent accidents. Mechanical enforcement does.**

---

*Created: December 17, 2025*
*Project: Ultimate Bug Scanner*
*Related: AGENTS.md, .claude/hooks/git_safety_guard.py*
