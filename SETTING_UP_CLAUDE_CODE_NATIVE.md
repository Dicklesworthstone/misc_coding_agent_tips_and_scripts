# Claude Code Native Install Fix

## Quick Fix

If `claude --version` shows an old version after installing natively:

```bash
# 1. Use explicit path in aliases (~/.zshrc)
alias cc='~/.local/bin/claude --dangerously-skip-permissions'

# 2. Update alias uses native updater
alias uca='~/.local/bin/claude update'

# 3. Remove stale symlinks
rm ~/.bun/bin/claude 2>/dev/null

# 4. Apply changes
source ~/.zshrc
```

---

## The Problem

After installing Claude Code via the native installer:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

You might still see an old version. This happens when a previous bun/npm installation appears earlier in your PATH.

**Symptoms:**
- `claude --version` shows old version despite fresh native install
- "Auto-update failed" errors
- `claude doctor` shows "Currently running: unknown"

---

## Diagnosis

```bash
which claude                    # Should be ~/.local/bin/claude
ls -la ~/.local/bin/claude      # Native install (correct)
ls -la ~/.bun/bin/claude        # Bun install (stale, if exists)
```

If `which claude` returns a bun or npm path, your shell is finding the wrong binary.

---

## The Fix

### 1. Update aliases to use explicit paths

In `~/.zshrc` or `~/.bashrc`:

```bash
# Before (finds wrong binary via PATH)
alias cc='claude --dangerously-skip-permissions'

# After (explicitly uses native install)
alias cc='~/.local/bin/claude --dangerously-skip-permissions'
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

### 4. Verify

```bash
~/.local/bin/claude --version   # Should show latest version
```

---

## What About Codex and Gemini CLI?

| Tool | Native Binary? | Recommendation |
|:-----|:---------------|:---------------|
| Claude Code | Yes | Use native installer (`~/.local/bin/claude`) |
| Codex | Yes (Rust) | Keep bun; it delivers the native binary anyway |
| Gemini CLI | No | Keep bun; no native option exists yet |

**Codex:** The bun/npm package is just a delivery mechanism. Your actual binary is a 40MB Mach-O arm64 executable at `~/.bun/install/global/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex`.

**Gemini CLI:** Users have [requested a native installer](https://github.com/google-gemini/gemini-cli/discussions/1640), but it doesn't exist yet. Homebrew still requires Node.js as a dependency.

---

*Last updated: January 2026*
