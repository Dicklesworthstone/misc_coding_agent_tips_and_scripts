# Ghostty Terminfo for Remote Machines

> **The problem:** You SSH into your remote server and press the numpad Enter key. Instead of a newline, you see `[57414u` garbage in your terminal.
>
> **The solution:** Install Ghostty's terminfo database on your remote machines so they understand the Kitty keyboard protocol.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                                                                            │
│  You press: [Numpad Enter]                                                 │
│                                                                            │
│  ┌─────────────────┐         ┌─────────────────┐         ┌──────────────┐  │
│  │     Ghostty     │ ──────▶ │   SSH tunnel    │ ──────▶ │ Remote bash  │  │
│  │  (sends \e[57414u)        │                 │         │              │  │
│  └─────────────────┘         └─────────────────┘         └──────────────┘  │
│                                                                 │          │
│                                                                 ▼          │
│                                           ┌──────────────────────────────┐ │
│                                           │ Without terminfo:            │ │
│                                           │   bash doesn't recognize     │ │
│                                           │   \e[57414u, prints literal  │ │
│                                           │                              │ │
│                                           │ With terminfo:               │ │
│                                           │   bash knows this = Enter    │ │
│                                           └──────────────────────────────┘ │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [Quick Fix](#quick-fix)
- [The Problem Explained](#the-problem-explained)
- [One-Time Setup Per Machine](#one-time-setup-per-machine)
- [Automating for Multiple Servers](#automating-for-multiple-servers)
- [Troubleshooting](#troubleshooting)

---

## Quick Fix

From your Mac (with Ghostty installed), run:

```bash
infocmp -x xterm-ghostty | ssh user@your-server 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
```

That's it. Reconnect and numpad Enter (and other special keys) will work correctly.

---

## The Problem Explained

### What is `[57414u`?

When you see `[57414u` in your terminal, you're seeing a raw escape sequence that your remote shell doesn't understand.

| Sequence | Meaning |
|:---------|:--------|
| `\e[57414u` | Kitty keyboard protocol encoding for numpad Enter |
| `57414` | Unicode codepoint for KP_Enter |
| `u` | Kitty protocol suffix |

### Why Does This Happen?

```
1. Ghostty advertises: "I support the Kitty keyboard protocol"
   (via TERM=xterm-ghostty and terminal queries)

2. Your local shell enables enhanced keyboard mode

3. You SSH to a remote server

4. Remote server sees TERM=xterm-ghostty but has no idea what that means

5. Applications on the remote try to use Kitty protocol features

6. Remote bash/zsh/apps don't understand the escape sequences → garbage output
```

### The Kitty Keyboard Protocol

Modern terminals like Ghostty, Kitty, and WezTerm support an enhanced keyboard protocol that can:

- Distinguish numpad Enter from regular Enter
- Report key release events
- Handle modifier keys more precisely
- Support more key combinations

This requires both the terminal and the remote system to understand the protocol. The **terminfo database** tells the remote system how to interpret these sequences.

---

## One-Time Setup Per Machine

### From Your Mac

```bash
# Replace with your actual server details
ssh -i ~/.ssh/your-key user@your-server 'mkdir -p ~/.terminfo'
infocmp -x xterm-ghostty | ssh -i ~/.ssh/your-key user@your-server 'tic -x -o ~/.terminfo -'
```

### What This Does

| Command | Purpose |
|:--------|:--------|
| `infocmp -x xterm-ghostty` | Export Ghostty's terminfo as text |
| `ssh ... 'mkdir -p ~/.terminfo'` | Create user terminfo directory |
| `tic -x -o ~/.terminfo -` | Compile terminfo on remote, install to user dir |

### Verify Installation

```bash
ssh user@your-server 'ls -la ~/.terminfo/x/xterm-ghostty'
```

Expected output:
```
-rw-rw-r-- 1 user user 3842 Jan  7 12:00 /home/user/.terminfo/x/xterm-ghostty
```

---

## Automating for Multiple Servers

### Shell Function

Add to your `~/.zshrc`:

```bash
# Push Ghostty terminfo to a remote host
ghostty_push_terminfo() {
  local host="$1"
  if [[ -z "$host" ]]; then
    echo "Usage: ghostty_push_terminfo <ssh-host>" >&2
    echo "Example: ghostty_push_terminfo ubuntu@dev-server.local" >&2
    return 1
  fi
  echo "Installing Ghostty terminfo on $host..."
  infocmp -x xterm-ghostty | ssh "$host" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
  echo "Done. Reconnect to $host to use the new terminfo."
}
```

Usage:

```bash
ghostty_push_terminfo ubuntu@dev-server.local
ghostty_push_terminfo admin@ci-runner.internal
ghostty_push_terminfo deploy@prod-web-01.example.com
```

### Batch Script for All Servers

If you have many servers, create a script:

```bash
#!/bin/bash
# push-terminfo-all.sh
# Push Ghostty terminfo to all development servers

SERVERS=(
  "ubuntu@dev-server.local"
  "ubuntu@staging.example.com"
  "deploy@prod-web-01.example.com"
  "deploy@prod-web-02.example.com"
  "admin@ci-runner.internal"
)

for server in "${SERVERS[@]}"; do
  echo "→ $server"
  if infocmp -x xterm-ghostty | ssh "$server" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -' 2>/dev/null; then
    echo "  ✓ Success"
  else
    echo "  ✗ Failed (check SSH access)"
  fi
done
```

### SSH Config Integration

If you use custom SSH keys or ports, ensure your `~/.ssh/config` is set up:

```
Host dev-server
    HostName 10.0.0.50
    User ubuntu
    IdentityFile ~/.ssh/dev_server_key

Host staging
    HostName staging.example.com
    User ubuntu
    IdentityFile ~/.ssh/staging_key

Host prod-*
    User deploy
    IdentityFile ~/.ssh/prod_key
```

Then simply:

```bash
ghostty_push_terminfo dev-server
ghostty_push_terminfo staging
```

---

## Alternative: Set TERM on SSH

If you can't install terminfo on the remote (no write access, ephemeral containers), force a compatible TERM:

```bash
# In your SSH alias
alias myserver='TERM=xterm-256color ssh user@myserver'

# Or in ~/.ssh/config
Host myserver
    SetEnv TERM=xterm-256color
```

**Trade-off:** You lose Ghostty-specific features (enhanced keyboard, etc.) but avoid the garbage characters.

---

## System-Wide Installation

If you have sudo access and want terminfo available to all users:

```bash
# Install to system terminfo directory
infocmp -x xterm-ghostty | ssh user@server 'sudo tic -x -'
```

This installs to `/usr/share/terminfo/` (or `/etc/terminfo/` depending on distro).

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Still seeing `[57414u` | Terminfo not installed or not found | Verify `~/.terminfo/x/xterm-ghostty` exists |
| `tic: command not found` | ncurses not installed on remote | `sudo apt install ncurses-bin` |
| `infocmp: terminal not found` | Ghostty terminfo not on local Mac | Reinstall Ghostty or check `$TERM` |
| Permission denied | Can't write to `~/.terminfo` | Check directory permissions |
| Works for bash, not for vim/tmux | App using wrong TERM | Ensure `$TERM` is `xterm-ghostty` |

### Verify TERM is Correct

On the remote:

```bash
echo $TERM
# Should output: xterm-ghostty
```

If it shows something else (like `xterm-256color`), check:

1. Your SSH client isn't overriding TERM
2. Remote `.bashrc`/`.zshrc` isn't resetting TERM
3. tmux/screen isn't changing TERM

### Check terminfo Database

```bash
# On remote, check if terminfo is found
infocmp xterm-ghostty >/dev/null 2>&1 && echo "Found" || echo "Not found"

# List terminfo search path
toe -a 2>/dev/null | grep ghostty
```

### The `tic` Warning

You might see:

```
"<stdin>", line 2, col 31, terminal 'xterm-ghostty': older tic versions may treat the description field as an alias
```

This is harmless. The terminfo was installed correctly despite the warning.

---

## Which Keys Are Affected?

The Kitty keyboard protocol affects these keys most noticeably:

| Key | Without terminfo | With terminfo |
|:----|:-----------------|:--------------|
| Numpad Enter | `[57414u` | Works correctly |
| Numpad numbers | May show escape codes | Works correctly |
| Ctrl+Shift+Letter | May not register | Works correctly |
| Function keys (F13+) | May show garbage | Works correctly |

---

## Quick Reference

### One-Liner Install

```bash
infocmp -x xterm-ghostty | ssh USER@HOST 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
```

### Shell Function

```bash
ghostty_push_terminfo() {
  local host="$1"
  [[ -z "$host" ]] && { echo "Usage: ghostty_push_terminfo <host>" >&2; return 1; }
  infocmp -x xterm-ghostty | ssh "$host" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
}
```

### Fallback (No Terminfo)

```bash
alias myserver='TERM=xterm-256color ssh user@myserver'
```

### Files Modified

| Location | File | Purpose |
|:---------|:-----|:--------|
| Remote | `~/.terminfo/x/xterm-ghostty` | Compiled terminfo database |
| Local | `~/.zshrc` | Optional helper function |

---

*Last updated: January 2026*
