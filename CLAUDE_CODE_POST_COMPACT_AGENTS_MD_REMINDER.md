# 🔄 Post-Compaction AGENTS.md Reminder for Claude Code

<p align="center">
  <strong>Never lose project context again</strong>
</p>

<p align="center">
  <a href="#quick-install"><img src="https://img.shields.io/badge/install-one--liner-brightgreen?style=flat-square" alt="Install"></a>
  <a href="#how-it-works"><img src="https://img.shields.io/badge/hook-SessionStart-blue?style=flat-square" alt="Hook Type"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/requires-jq%20%2B%20python3-orange?style=flat-square" alt="Requirements"></a>
</p>

---

> 💡 **The Problem:** After context compaction, Claude often "forgets" project-specific conventions documented in AGENTS.md. This hook automatically reminds Claude to re-read AGENTS.md after every compaction, ensuring consistent behavior throughout long coding sessions.

---

## ⚡ Quick Install

```bash
# One-liner install (global)
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-post-compact-reminder.sh | bash

# Or download and run locally
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-post-compact-reminder.sh -o install-post-compact-reminder.sh
chmod +x install-post-compact-reminder.sh
./install-post-compact-reminder.sh

# Restart Claude Code after installation
```

See [Automated Setup Script](#automated-setup-script) below for the full installer.

---

## 🎯 The Problem

During long coding sessions, Claude Code compacts the conversation to stay within context limits. After compaction:

| ❌ Lost | Description |
|:--------|:------------|
| 📋 **AGENTS.md conventions** | Project rules and guidelines |
| 🔧 **Code patterns** | Architectural decisions and style |
| 🤝 **Multi-agent coordination** | Collaboration instructions |
| 📝 **Style guidelines** | Formatting and naming conventions |

**This hook solves all of these** by automatically injecting a reminder after every compaction.

---

## ⚙️ How It Works

Claude Code's `SessionStart` hook fires with `source: "compact"` when the session restarts after compaction. The hook checks this field and injects a reminder message:

```
<post-compact-reminder>
Context was just compacted. Please reread AGENTS.md to refresh your understanding
of project conventions and agent coordination patterns.
</post-compact-reminder>
```

Claude sees this reminder and re-reads AGENTS.md, restoring project context.

### Hook Flow

```
┌──────────────────┐
│ Context fills up │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Compaction     │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────┐
│ SessionStart (source: "compact") │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ Hook injects AGENTS.md reminder  │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│ Claude re-reads AGENTS.md        │
└──────────────────────────────────┘
```

### File Structure

```
~/.claude/
└── settings.json                 # Hook configuration

~/.local/bin/
└── claude-post-compact-reminder  # Reminder script
```

### Configuration

`~/.claude/settings.json` (partial):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/claude-post-compact-reminder"
          }
        ]
      }
    ]
  }
}
```

The `"matcher": "compact"` ensures the hook only fires after compaction, not on every session start.

---

## 🚀 Automated Setup Script

The installer supports multiple options:

```bash
# Install (idempotent - safe to run multiple times)
./install-post-compact-reminder.sh

# Preview changes without modifying anything
./install-post-compact-reminder.sh --dry-run

# Reinstall even if already at latest version
./install-post-compact-reminder.sh --force

# Remove the hook completely
./install-post-compact-reminder.sh --uninstall

# Show help
./install-post-compact-reminder.sh --help
```

**Requirements:** `jq` and `python3` (auto-installed if missing on apt/brew/dnf/yum/pacman systems; Homebrew installs `python`, which provides `python3`).

<details>
<summary><strong>View full installer source</strong> (click to expand)</summary>

The full installer script is available at:
- [install-post-compact-reminder.sh on GitHub](https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-post-compact-reminder.sh)

Key features:
- **Version tracking** - Detects existing installations and compares versions
- **Idempotent** - Safe to run multiple times
- **`--dry-run`** - Preview changes without modifying anything
- **`--uninstall`** - Clean removal of both script and settings entry
- **`--force`** - Reinstall even if already at latest version
- **Dependency checking** - Validates jq and python3 before proceeding
- **Hook testing** - Verifies the hook works before declaring success

</details>

---

## 🔧 Manual Installation

If you prefer not to use the script:

1. Create the hook script at `~/.local/bin/claude-post-compact-reminder`:

```bash
#!/usr/bin/env bash
# Version: 1.0.0
# SessionStart hook: Remind Claude to reread AGENTS.md after compaction
# Input: JSON with session_id, source on stdin
#
# This hook fires when source="compact" (configured via matcher in settings.json)
# and outputs a reminder that Claude sees in its context.

set -e

# Read JSON input from Claude Code
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')

# Double-check source (belt and suspenders with the matcher)
if [[ "$SOURCE" == "compact" ]]; then
    cat <<'EOF'
<post-compact-reminder>
Context was just compacted. Please reread AGENTS.md to refresh your understanding of project conventions and agent coordination patterns.
</post-compact-reminder>
EOF
fi

# SessionStart hooks don't block, just exit 0
exit 0
```

2. Make it executable: `chmod +x ~/.local/bin/claude-post-compact-reminder`

3. Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/claude-post-compact-reminder"
          }
        ]
      }
    ]
  }
}
```

4. Restart Claude Code

---

## Testing

```bash
# Simulate post-compaction SessionStart
echo '{"session_id": "test-123", "source": "compact"}' | \
  ~/.local/bin/claude-post-compact-reminder

# Expected output:
# <post-compact-reminder>
# Context was just compacted. Please reread AGENTS.md...
# </post-compact-reminder>

# Simulate normal session start (no output expected)
echo '{"session_id": "test-123", "source": "startup"}' | \
  ~/.local/bin/claude-post-compact-reminder
```

---

## Customizing the Reminder

Edit `~/.local/bin/claude-post-compact-reminder` to customize the message:

```bash
if [[ "$SOURCE" == "compact" ]]; then
    cat <<'EOF'
<post-compact-reminder>
Your custom reminder message here.
- Re-read AGENTS.md
- Check the current task list
- Review recent commits
</post-compact-reminder>
EOF
fi
```

---

## Requirements

| Requirement | Purpose |
|:------------|:--------|
| `jq` | Parses JSON input from Claude Code |
| `python3` | Used by installer for JSON manipulation |
| `bash` | Script interpreter |
| Claude Code | The CLI tool this hook extends |

Install dependencies if missing:
```bash
# Ubuntu/Debian
sudo apt install jq python3

# macOS
brew install jq python

# Fedora/RHEL
sudo dnf install jq python3
```

---

## How SessionStart Differs from Other Hooks

| Hook | When it fires | Can block? | Use case |
|:-----|:--------------|:-----------|:---------|
| `SessionStart` | Session begins (startup, resume, clear, compact) | No | Inject context, set environment |
| `PreToolUse` | Before tool executes | Yes | Block dangerous commands |
| `PostToolUse` | After tool completes | No | Auto-format, lint |
| `UserPromptSubmit` | User sends message | Yes | Add context to prompts |

The `source` field in `SessionStart` input tells you why the session started:
- `"startup"` - Fresh session
- `"resume"` - Resumed from `--resume`, `--continue`, or `/resume`
- `"clear"` - After `/clear` command
- `"compact"` - Restarted after context compaction

**Tip:** You can use `matcher` to only fire for specific sources:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/claude-post-compact-reminder" }
        ]
      }
    ]
  }
}
```

---

## Related

- [DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md](DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md) - Block dangerous git/rm commands
- [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)

---

*Created: January 2026*
*Related: AGENTS.md, multi-agent coordination, context management*
