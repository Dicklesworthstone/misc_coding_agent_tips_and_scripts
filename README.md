# Misc Coding Agent Tips and Scripts

A collection of guides, tips, and configuration scripts for AI coding agents, development tools, and system setups. This repository documents best practices, workarounds, and configurations discovered through real-world usage of AI assistants and development environments.

## 📚 Contents

### 🤖 AI Agent Configuration & Safety

#### [Destructive Git Command Protection](DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md)
**Critical safety hook for Claude Code to prevent data loss**

On December 17, 2025, an AI agent accidentally destroyed hours of uncommitted work by running `git checkout --` on multiple files. This guide provides a mechanical enforcement system to prevent such incidents.

**What it does:**
- Blocks destructive git/filesystem commands before execution
- Uses Claude Code's PreToolUse hook system
- Protects against `git checkout --`, `git reset --hard`, `rm -rf`, and more
- Includes automated installation script for project-local or global setup

**Key Features:**
- Runs before bash commands execute (can block dangerous operations)
- Provides clear feedback explaining why commands are blocked
- Maintains allowlist for safe command variants
- Zero false positives on normal workflows

**Quick Install:**
```bash
# Project-local (current directory)
curl -fsSL [URL]/install-claude-git-guard.sh | bash

# Global (all projects)
curl -fsSL [URL]/install-claude-git-guard.sh | bash -s -- --global
```

> ⚠️ **Important:** Restart Claude Code after installation for hooks to take effect.

### 🔧 Development Tools & Setup

#### [Beads Setup Guide](BEADS_SETUP.md)
**Configuration guide for Beads project management tool**

Comprehensive setup instructions for using Beads in a repository, including sync branch configuration, common commands, and troubleshooting.

**Key Topics:**
- Initial setup with dedicated sync branches to avoid worktree conflicts
- Sync commands reference (`bd sync`, `bd sync --from-main`, etc.)
- Configuration management (`bd config`)
- Troubleshooting worktree errors and sync issues
- Health checks with `bd doctor`

**Quick Setup:**
```bash
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync
```

#### [Claude Code Native Install Fix](SETTING_UP_CLAUDE_CODE_NATIVE.md)
**Resolving PATH conflicts between native and bun/npm installations**

After installing Claude Code natively via `curl`, users may encounter version conflicts when older bun/npm installations remain in PATH. This guide diagnoses and fixes the issue.

**Symptoms:**
- `claude --version` shows old version despite fresh install
- "Auto-update failed" errors
- `claude doctor` shows "Currently running: unknown"

**The Fix:**
- Use explicit paths in shell aliases (`~/.local/bin/claude`)
- Update the update alias to use native updater
- Remove stale symlinks from bun/npm installations
- Comparison of native vs package manager installs for Claude Code, Codex, and Gemini CLI

#### [Moonlight Streaming Configuration](MOONLIGHT_CONFIG_DOC.md)
**Complete guide for remote desktop streaming with Moonlight and Sunshine**

Documents a working setup for streaming from a powerful Linux workstation (threadripperje with dual RTX 4090s) to a Mac client using Moonlight with AV1 encoding.

**Configuration:**
- Server: Sunshine on Hyprland (Wayland) with NVENC encoding
- Client: Custom Moonlight build with AV1 support
- Resolution: 3072x1728@30fps via AV1 codec
- Clipboard sync scripts and desktop switching utilities

**Common Issues Covered:**
- Display sleep/wake problems
- GPU AV1 support errors
- Fullscreen escape methods
- Clipboard synchronization workarounds
- NVIDIA persistence mode setup

**Quick Reference Commands:**
```bash
ml      # Start Moonlight streaming
trj     # SSH into remote server
wu      # Wake up remote display
cptl    # Copy clipboard to Linux
cpfm    # Copy clipboard from Mac
```

## 🎯 Use Cases

This repository is useful for:

- **AI Agent Users**: Configure safety guardrails and optimize tool usage
- **DevOps Engineers**: Learn from real-world tool configurations and workarounds
- **Remote Workers**: Set up high-performance remote desktop streaming
- **Development Teams**: Implement project management tools like Beads
- **System Administrators**: Document complex multi-tool configurations

## 🚀 Quick Start

1. **Browse the guides** in the table of contents above
2. **Identify the tools** you're using (Claude Code, Beads, Moonlight, etc.)
3. **Follow the relevant guide** for setup and configuration
4. **Check troubleshooting sections** if you encounter issues

## 🛡️ Safety First

If you use AI coding agents, **start with the Destructive Git Command Protection guide**. The hook system can prevent data loss from accidental destructive commands. This is especially important if multiple agents or developers work on the same codebase.

## 📖 Documentation Style

Each guide follows a consistent structure:

- **Problem Statement**: What issue does this solve?
- **Quick Reference**: Tables and commands for fast lookup
- **Configuration**: Complete setup instructions
- **Troubleshooting**: Common issues and solutions
- **Examples**: Real-world usage patterns

## 🤝 Contributing

These guides were created from real-world experience and incidents. If you have:

- Improvements to existing guides
- New configurations or workarounds
- Corrections or clarifications

Feel free to contribute via pull requests or issues.

## ⚙️ Tech Stack

Tools and technologies covered:

- **AI Agents**: Claude Code, Codex, Gemini CLI
- **Version Control**: Git, with safety hooks and best practices
- **Project Management**: Beads
- **Remote Desktop**: Moonlight, Sunshine, Hyprland
- **Package Managers**: bun, npm, native installers
- **Operating Systems**: macOS, Linux (Ubuntu/Arch)
- **Hardware**: NVIDIA GPUs, multi-monitor setups

## 📝 License

This repository contains documentation and configuration files. Use freely for personal or commercial projects.

## 🔗 Related Resources

- [Claude Code Documentation](https://docs.anthropic.com/claude/docs/claude-code)
- [Beads Project](https://github.com/beads-project/beads)
- [Moonlight Game Streaming](https://moonlight-stream.org/)
- [Sunshine Streaming Server](https://github.com/LizardByte/Sunshine)

---

*Last Updated: December 2025*
