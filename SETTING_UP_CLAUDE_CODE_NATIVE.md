# Fixing Claude Code: Native Install vs Bun/NPM Conflict

## The Problem

After installing Claude Code natively (via `curl`), you still see the old version and get "Auto-update failed" errors. This happens because your shell finds an older bun/npm-installed version first in your PATH.

Command to install Claude Code natively is:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Symptoms:**
- `claude --version` shows old version despite fresh native install
- "Auto-update failed · Try claude doctor or npm i -g @anthropic-ai/claude-code" message
- `claude doctor` shows "Currently running: unknown"

## Diagnosis

Check where your `claude` commands point:

```bash
which claude
ls -la ~/.local/bin/claude      # Native install (correct)
ls -la ~/.bun/bin/claude        # Bun install (stale)
```

If `which claude` returns a bun or npm path instead of `~/.local/bin/claude`, that's the conflict.

## The Fix

### 1. Update aliases to use explicit paths

In your `~/.zshrc` (or `~/.bashrc`), change any `claude` aliases to use the full path:

```bash
# Before (finds wrong binary via PATH)
alias cc='claude --dangerously-skip-permissions'

# After (explicitly uses native install)
alias cc='~/.local/bin/claude --dangerously-skip-permissions'

# Others:
alias gmi='gemini --yolo --model gemini-3-pro-preview'
alias cod='codex --dangerously-bypass-approvals-and-sandbox --search -m gpt-5.2 -c model_reasoning_effort="xhigh" -c model_reasoning_summary_format=experimental'
```

### 2. Update your update alias

The native installer has a built-in update command:

```bash
# Before
alias uca='bun install -g @anthropic-ai/claude-code@latest'

# After (updates all three coding agent CLIs)
alias uca='~/.local/bin/claude update && bun install -g @openai/codex@latest && bun install -g @google/gemini-cli@latest'
```

### 3. Remove stale symlinks

```bash
rm ~/.bun/bin/claude 2>/dev/null
rm ~/.bun/install/global/node_modules/.bin/claude 2>/dev/null
```

### 4. Apply changes

```bash
source ~/.zshrc
```

## Verify

```bash
~/.local/bin/claude --version  # Should show latest version
```

## What About Codex and Gemini CLI?

| Tool | Native Binary? | Recommendation |
|------|----------------|----------------|
| Claude Code | ✅ Yes | Use native installer (`~/.local/bin/claude`) |
| Codex | ✅ Yes (Rust) | Keep bun—it delivers the native binary anyway |
| Gemini CLI | ❌ No | Keep bun—no native option exists yet |

**Codex:** The bun/npm package is just a delivery mechanism. Your actual binary is a 40MB Mach-O arm64 executable at `~/.bun/install/global/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex`. You're already running native code.

**Gemini CLI:** Users have [requested a native installer](https://github.com/google-gemini/gemini-cli/discussions/1640), but it doesn't exist yet. Homebrew still requires Node.js as a dependency. Stick with bun.
