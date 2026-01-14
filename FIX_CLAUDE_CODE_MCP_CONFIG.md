# Fix Claude Code MCP Configuration

## Quick Fix

When your Claude Code MCP server setup gets wiped out:

```bash
fix_cc_mcp
```

That's it. The script restores both `mcp-agent-mail` and `morph-mcp` servers automatically.

---

## The Problem

Claude Code stores MCP server configurations in `~/.claude.json`. These can get wiped out by:

- Fresh Claude Code installations
- Config file corruption
- Accidental deletion
- Updates that reset settings

**Symptoms:**
- MCP tools unavailable in Claude Code sessions
- "Server not connected" errors
- `claude mcp list` shows empty or missing servers

The manual fix involves two steps:
1. Running the full MCP Agent Mail installer (slow, does much more than needed)
2. Manually adding morph-mcp with a long command

---

## The Solution

A single script that does only the MCP config restoration—nothing else.

### Installation

```bash
# Create the script
cat > ~/.local/bin/fix_cc_mcp << 'SCRIPT'
#!/usr/bin/env bash
# fix_cc_mcp - Restore Claude Code MCP server configuration
# Fixes mcp-agent-mail and morph-mcp servers without running full install

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_ok()   { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_err()  { echo -e "${RED}✗${NC} $*" >&2; }
log_info() { echo -e "${BLUE}→${NC} $*"; }

# Configuration
MCP_AGENT_MAIL_DIR="${MCP_AGENT_MAIL_DIR:-${HOME}/mcp_agent_mail}"
MCP_URL="${MCP_URL:-http://127.0.0.1:8765/mcp/}"
MORPH_API_KEY="${MORPH_API_KEY:-YOUR_MORPH_API_KEY_HERE}"
SCOPE="${MCP_SCOPE:-user}"

echo "═══════════════════════════════════════════════════════════════"
echo "  fix_cc_mcp - Claude Code MCP Configuration Fixer"
echo "═══════════════════════════════════════════════════════════════"
echo

# Check for claude CLI
if ! command -v claude &>/dev/null; then
    log_err "claude CLI not found. Please install Claude Code first."
    exit 1
fi

# Get bearer token - check multiple sources in order of preference
TOKEN=""

# 1. Check environment variable first (allows override)
if [[ -n "${MCP_AGENT_MAIL_TOKEN:-}" ]]; then
    TOKEN="${MCP_AGENT_MAIL_TOKEN}"
    log_info "Using token from MCP_AGENT_MAIL_TOKEN env var"
fi

# 2. Check mcp_agent_mail .env file
ENV_FILE_EXISTS=false
if [[ -z "${TOKEN}" && -f "${MCP_AGENT_MAIL_DIR}/.env" ]]; then
    ENV_FILE_EXISTS=true
    # Strip quotes and whitespace from token value
    TOKEN=$(grep -E '^HTTP_BEARER_TOKEN=' "${MCP_AGENT_MAIL_DIR}/.env" 2>/dev/null \
        | sed 's/^HTTP_BEARER_TOKEN=//' \
        | tr -d '"'"'" \
        | tr -d '[:space:]' || true)
    if [[ -n "${TOKEN}" ]]; then
        log_info "Using token from ${MCP_AGENT_MAIL_DIR}/.env"
    fi
fi

# 3. Check existing ~/.claude.json config
if [[ -z "${TOKEN}" && -f "${HOME}/.claude.json" ]]; then
    if [[ "${ENV_FILE_EXISTS}" == "true" ]]; then
        log_warn "No HTTP_BEARER_TOKEN found in ${MCP_AGENT_MAIL_DIR}/.env"
    else
        log_warn "${MCP_AGENT_MAIL_DIR}/.env not found"
    fi
    log_warn "Looking in ~/.claude.json..."
    TOKEN=$(grep -o '"Authorization": "Bearer [^"]*"' "${HOME}/.claude.json" 2>/dev/null \
        | head -1 \
        | sed 's/.*Bearer //' \
        | tr -d '"' || true)
    if [[ -n "${TOKEN}" ]]; then
        log_info "Using token from ~/.claude.json"
    fi
fi

# Fail if no token found
if [[ -z "${TOKEN}" ]]; then
    log_err "Could not find bearer token."
    log_err "Options:"
    log_err "  1. Set MCP_AGENT_MAIL_TOKEN env var"
    log_err "  2. Ensure ${MCP_AGENT_MAIL_DIR}/.env has HTTP_BEARER_TOKEN=..."
    log_err "  3. Run the full installer: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh | bash -s -- --yes"
    exit 1
fi

# Display token (safely handle short tokens)
if [[ ${#TOKEN} -ge 16 ]]; then
    log_ok "Found bearer token: ${TOKEN:0:8}...${TOKEN: -8}"
else
    log_ok "Found bearer token: ${TOKEN:0:4}..."
fi

# Remove existing servers first (ignore errors if they don't exist)
log_info "Removing existing MCP server configs..."
claude mcp remove mcp-agent-mail --scope "${SCOPE}" 2>/dev/null || true
claude mcp remove morph-mcp --scope "${SCOPE}" 2>/dev/null || true

# Add mcp-agent-mail (HTTP transport with auth header)
log_info "Adding mcp-agent-mail server..."
if claude mcp add mcp-agent-mail "${MCP_URL}" \
    --transport http \
    --header "Authorization: Bearer ${TOKEN}" \
    --scope "${SCOPE}"; then
    log_ok "mcp-agent-mail added successfully"
else
    log_err "Failed to add mcp-agent-mail"
    exit 1
fi

# Add morph-mcp (stdio transport with npx)
log_info "Adding morph-mcp server..."
if claude mcp add morph-mcp \
    -e "MORPH_API_KEY=${MORPH_API_KEY}" \
    -e "ENABLED_TOOLS=warp_grep" \
    --scope "${SCOPE}" \
    -- npx -y @morphllm/morphmcp; then
    log_ok "morph-mcp added successfully"
else
    log_err "Failed to add morph-mcp"
    exit 1
fi

echo
log_info "Verifying MCP server configuration..."
claude mcp list 2>&1 || true

echo
echo "═══════════════════════════════════════════════════════════════"
log_ok "Claude Code MCP configuration restored!"
echo "═══════════════════════════════════════════════════════════════"
SCRIPT

# Make executable
chmod +x ~/.local/bin/fix_cc_mcp
```

### Configure Your API Key

Edit the script to add your Morph API key:

```bash
# Open in your editor
nano ~/.local/bin/fix_cc_mcp

# Find this line and replace YOUR_MORPH_API_KEY_HERE:
MORPH_API_KEY="${MORPH_API_KEY:-YOUR_MORPH_API_KEY_HERE}"
```

Or set it via environment variable in `~/.zshrc`:

```bash
export MORPH_API_KEY="sk-your-actual-key-here"
```

---

## How It Works

The script uses the `claude mcp` CLI commands to manage MCP servers:

```bash
# Remove existing (if any)
claude mcp remove mcp-agent-mail --scope user
claude mcp remove morph-mcp --scope user

# Add mcp-agent-mail (HTTP transport)
claude mcp add mcp-agent-mail "http://127.0.0.1:8765/mcp/" \
    --transport http \
    --header "Authorization: Bearer <token>" \
    --scope user

# Add morph-mcp (stdio transport via npx)
claude mcp add morph-mcp \
    -e "MORPH_API_KEY=<key>" \
    -e "ENABLED_TOOLS=warp_grep" \
    --scope user \
    -- npx -y @morphllm/morphmcp
```

### Token Discovery

The script finds the bearer token for `mcp-agent-mail` by checking (in order):

| Priority | Source | Description |
|:---------|:-------|:------------|
| 1 | `MCP_AGENT_MAIL_TOKEN` env var | Explicit override |
| 2 | `~/mcp_agent_mail/.env` | MCP Agent Mail's config file |
| 3 | `~/.claude.json` | Existing Claude Code config |

---

## Configuration Options

Override defaults via environment variables:

| Variable | Default | Description |
|:---------|:--------|:------------|
| `MCP_AGENT_MAIL_TOKEN` | (auto-detected) | Bearer token for authentication |
| `MCP_AGENT_MAIL_DIR` | `~/mcp_agent_mail` | Location of MCP Agent Mail install |
| `MCP_URL` | `http://127.0.0.1:8765/mcp/` | MCP Agent Mail server URL |
| `MORPH_API_KEY` | (in script) | Your Morph API key |
| `MCP_SCOPE` | `user` | Config scope: `user`, `local`, or `project` |

**Example with overrides:**

```bash
MCP_URL="http://localhost:9000/mcp/" MCP_SCOPE=project fix_cc_mcp
```

---

## What Gets Configured

After running, `~/.claude.json` will contain:

```json
{
  "mcpServers": {
    "mcp-agent-mail": {
      "type": "http",
      "url": "http://127.0.0.1:8765/mcp/",
      "headers": {
        "Authorization": "Bearer <your-token>"
      }
    },
    "morph-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@morphllm/morphmcp"],
      "env": {
        "MORPH_API_KEY": "<your-key>",
        "ENABLED_TOOLS": "warp_grep"
      }
    }
  }
}
```

---

## Comparison: Full Installer vs fix_cc_mcp

| | Full Installer | fix_cc_mcp |
|:--|:---------------|:-----------|
| Runtime | 30-60 seconds | 2-3 seconds |
| Updates MCP Agent Mail | Yes | No |
| Clones/pulls git repo | Yes | No |
| Installs Python deps | Yes | No |
| Configures Claude hooks | Yes | No |
| Sets up other agents | Yes | No |
| **Restores MCP config** | **Yes** | **Yes** |

Use `fix_cc_mcp` when you only need to restore the MCP configuration.
Use the full installer when you need to update MCP Agent Mail itself.

---

## Adding More MCP Servers

To add additional servers to the script, append more `claude mcp add` commands:

```bash
# Example: Add a custom MCP server
claude mcp add my-custom-server "http://localhost:3000/mcp" \
    --transport http \
    --scope user
```

Or for stdio-based servers:

```bash
claude mcp add another-server \
    -e "API_KEY=${ANOTHER_API_KEY}" \
    --scope user \
    -- npx -y @example/mcp-server
```

---

## Troubleshooting

### "claude CLI not found"

Install Claude Code first:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

### "Could not find bearer token"

Run the full MCP Agent Mail installer to generate a token:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh" | bash -s -- --yes
```

### Server shows "not connected" after running

Ensure the MCP Agent Mail server is running:

```bash
cd ~/mcp_agent_mail && ./scripts/run_server_with_token.sh
```

Or use the `am` alias if installed:

```bash
am  # Starts the server
```

---

*Last updated: January 2026*
