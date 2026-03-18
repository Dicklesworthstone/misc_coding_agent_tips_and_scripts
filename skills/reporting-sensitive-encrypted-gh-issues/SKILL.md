---
name: reporting-sensitive-encrypted-gh-issues
description: >-
  Encrypt, submit, scan, and decrypt age-encrypted GitHub Issues (X25519).
  Use when reporting vulnerabilities, scanning for encrypted issues, or
  decrypting security reports.
---

<!-- TOC: Dispatch | Encrypt & Submit | Scan & Decrypt | Format | Commands | Notes -->

# Encrypted GitHub Issues — gh-issue-decrypt

**If `gh-issue-decrypt` is not installed**, run:
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/gh-issue-decrypt?$(date +%s)" | bash -s -- --install
```

## What Do You Need?

| Goal | Command |
|------|---------|
| Submit encrypted security report | `echo "details" \| gh-issue-decrypt --encrypt PUBKEY --submit OWNER/REPO` |
| Scan repo for encrypted issues | `gh-issue-decrypt OWNER/REPO` |
| Decrypt a specific issue | `gh-issue-decrypt OWNER/REPO 42` |
| Set up receiving (install + keygen) | `gh-issue-decrypt --install` |
| Full interactive guide | `gh-issue-decrypt` (no args) |

## Encrypt & Submit a Security Report

```bash
# 1. Find the project's age public key in their README:
#    grep -oE 'age1[a-z0-9]{58}' README.md

# 2. Encrypt + submit in one command:
echo "SQL injection in /api/users — WHERE clause interpolates user input. \
Affects v2.0-2.4. PoC: curl '/api/users?id=1 OR 1=1'" \
  | gh-issue-decrypt --encrypt age1PUBKEY_FROM_README \
    --submit OWNER/REPO --title "Security: SQLi in /api/users"

# Or encrypt only (outputs [enc:age] block for manual pasting):
echo "details" | gh-issue-decrypt --encrypt age1PUBKEY_FROM_README
```

The script auto-installs `age` if missing. Requires `gh auth login` for `--submit`.

## Scan & Decrypt Issues

```bash
gh-issue-decrypt OWNER/REPO          # all open issues
gh-issue-decrypt OWNER/REPO 42       # specific issue + comments
gh-issue-decrypt --json OWNER/REPO   # machine-readable output
```

Output:

```
-> Scanning open issues in OWNER/REPO...
=== Issue #42 -- encrypted block(s) found ===
ok Block #1 decrypted:
SQL injection in /api/users — WHERE clause interpolates user input.
```

Private key: `~/.config/age/issuebot.key` (set `AGE_KEY` env var to override).

## Issue Format

Encrypted blocks in issue bodies look like:

```
[enc:age]
-----BEGIN AGE ENCRYPTED FILE-----
YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSA...
-----END AGE ENCRYPTED FILE-----
[/enc:age]
```

The `[enc:age]` markers are optional — bare `BEGIN AGE ENCRYPTED FILE` headers are detected too.
Plaintext and encrypted blocks can be mixed in the same issue.

## All Commands

| Command | Purpose |
|---------|---------|
| `gh-issue-decrypt` | Quickstart guide (detects local keys) |
| `gh-issue-decrypt OWNER/REPO` | Scan open issues |
| `gh-issue-decrypt OWNER/REPO 42` | Decrypt specific issue |
| `gh-issue-decrypt --encrypt PUBKEY` | Encrypt stdin → armored block |
| `gh-issue-decrypt --encrypt PUBKEY --submit O/R --title "T"` | Encrypt + create issue |
| `gh-issue-decrypt --json OWNER/REPO` | JSON output |
| `gh-issue-decrypt --install` | Install age + gh + keygen |
| `gh-issue-decrypt --keygen` | Generate age keypair |
| `gh-issue-decrypt --key FILE` | Alternate private key |

## Notes

- **No authentication:** age encrypts but doesn't prove sender identity. Pair with SSH signatures or minisign if sender verification matters.
- **Back up the private key** (`~/.config/age/issuebot.key`) — loss means encrypted messages are unrecoverable.
- Public keys are 62 chars: `age1` + 58 lowercase alphanumeric (Bech32). Safe to publish in READMEs.
