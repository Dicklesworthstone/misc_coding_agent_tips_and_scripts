# HashiCorp Vault HA Cluster with Integrated Raft Storage

> **The problem:** You need a secrets manager for API keys, database credentials, and certificates. A single Vault instance is a single point of failure. If it goes down, your applications can't access secrets.
>
> **The solution:** A 3-node Vault cluster using Raft consensus for high availability. If one node fails, the cluster elects a new leader and keeps running.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VAULT HA CLUSTER                                     │
│                                                                              │
│   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐        │
│   │                  │   │                  │   │                  │        │
│   │   NODE 1         │   │   NODE 2         │   │   NODE 3         │        │
│   │   (Leader)       │   │   (Follower)     │   │   (Follower)     │        │
│   │                  │   │                  │   │                  │        │
│   │   10.0.1.10      │   │   10.0.1.11      │   │   10.0.1.12      │        │
│   │   :8200 API      │   │   :8200 API      │   │   :8200 API      │        │
│   │   :8201 Cluster  │   │   :8201 Cluster  │   │   :8201 Cluster  │        │
│   │                  │   │   (standby)      │   │   (standby)      │        │
│   └────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘        │
│            │                      │                      │                  │
│            └──────────────────────┼──────────────────────┘                  │
│                                   │                                         │
│                          Raft Consensus                                     │
│                    (automatic leader election)                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Leader handles all writes. Followers replicate data and forward requests.
If leader fails → automatic election → new leader in seconds.
```

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Node 1: Initialize the Leader](#node-1-initialize-the-leader)
- [Nodes 2-3: Join the Cluster](#nodes-2-3-join-the-cluster)
- [Unsealing the Cluster](#unsealing-the-cluster)
- [Verifying Cluster Health](#verifying-cluster-health)
- [Key Management Best Practices](#key-management-best-practices)
- [Maintenance Commands](#maintenance-commands)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Why Raft?

| Storage Backend | Pros | Cons |
|:----------------|:-----|:-----|
| **Integrated Raft** | No external dependencies, automatic HA | Requires 3+ nodes |
| Consul | Battle-tested, service mesh | Separate cluster to manage |
| etcd | K8s-native if already using | Another component |
| S3/GCS | Simple backup | No HA (single writer) |

Integrated Raft is the recommended choice for new deployments. It's built into Vault and requires no external services.

### Terminology

| Term | Meaning |
|:-----|:--------|
| **Leader** | Active node that handles all writes |
| **Follower** | Standby node that replicates from leader |
| **Sealed** | Vault is locked; can't read/write secrets |
| **Unsealed** | Vault is unlocked and operational |
| **Unseal Key** | Key(s) needed to unseal Vault after restart |
| **Root Token** | Initial superuser token for setup |

---

## Prerequisites

| Component | Requirement |
|:----------|:------------|
| Nodes | 3 servers (odd number for quorum) |
| OS | Linux (Ubuntu 22.04+ recommended) |
| Ports | 8200 (API), 8201 (cluster) |
| Network | Nodes can reach each other on both ports |
| Storage | ~1GB for Raft data per node |
| TLS | Recommended for production |

### Install Vault on All Nodes

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install
sudo apt update && sudo apt install vault

# Verify
vault version
```

---

## Node 1: Initialize the Leader

### Step 1: Create Configuration

Create `/etc/vault.d/vault.hcl` on the first node:

```hcl
# Cluster identification
cluster_name = "my-vault-cluster"

# API listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true  # Enable TLS in production!
}

# Raft storage configuration
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "node1"

  retry_join {
    leader_api_addr = "http://10.0.1.10:8200"
  }
  retry_join {
    leader_api_addr = "http://10.0.1.11:8200"
  }
  retry_join {
    leader_api_addr = "http://10.0.1.12:8200"
  }
}

# Cluster communication
cluster_addr = "http://10.0.1.10:8201"
api_addr     = "http://10.0.1.10:8200"

# Disable memory locking (enable in production with proper permissions)
disable_mlock = true

# UI
ui = true
```

### Step 2: Create Data Directory

```bash
sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /opt/vault/data
```

### Step 3: Start Vault

```bash
sudo systemctl enable vault
sudo systemctl start vault

# Check status
sudo systemctl status vault
```

### Step 4: Initialize the Cluster

This creates unseal keys and the root token. **Only run this on the first node, once.**

```bash
export VAULT_ADDR='http://127.0.0.1:8200'

# Initialize with Shamir's Secret Sharing
# -key-shares: total number of unseal key parts
# -key-threshold: number needed to unseal
vault operator init -key-shares=5 -key-threshold=3
```

**Output (SAVE THIS SECURELY):**
```
Unseal Key 1: abc123...
Unseal Key 2: def456...
Unseal Key 3: ghi789...
Unseal Key 4: jkl012...
Unseal Key 5: mno345...

Initial Root Token: hvs.xxxxxxxxxxxx

Vault initialized with 5 key shares and a key threshold of 3.
```

> **CRITICAL:** Store these keys securely. Distribute them to different people/locations. You need 3 of 5 to unseal. If you lose enough keys, your data is permanently inaccessible.

### Step 5: Unseal Node 1

```bash
# Run this 3 times with 3 different keys
vault operator unseal  # Enter key 1
vault operator unseal  # Enter key 2
vault operator unseal  # Enter key 3

# Check status
vault status
# Should show: Sealed: false
```

---

## Nodes 2-3: Join the Cluster

### Step 1: Create Configuration

Create `/etc/vault.d/vault.hcl` on nodes 2 and 3. Only change `node_id`, `cluster_addr`, and `api_addr`:

**Node 2:**
```hcl
cluster_name = "my-vault-cluster"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "node2"  # Unique per node

  retry_join {
    leader_api_addr = "http://10.0.1.10:8200"
  }
  retry_join {
    leader_api_addr = "http://10.0.1.11:8200"
  }
  retry_join {
    leader_api_addr = "http://10.0.1.12:8200"
  }
}

cluster_addr = "http://10.0.1.11:8201"  # This node's address
api_addr     = "http://10.0.1.11:8200"

disable_mlock = true
ui = true
```

**Node 3:** Same pattern with `node_id = "node3"`, `cluster_addr = "http://10.0.1.12:8201"`, etc.

### Step 2: Start and Unseal

```bash
# Create data directory
sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /opt/vault/data

# Start Vault
sudo systemctl enable vault
sudo systemctl start vault

# Unseal with the SAME keys from Node 1
export VAULT_ADDR='http://127.0.0.1:8200'
vault operator unseal  # Key 1
vault operator unseal  # Key 2
vault operator unseal  # Key 3
```

The node automatically joins the cluster via `retry_join`.

---

## Unsealing the Cluster

After a restart (maintenance, power outage, etc.), all nodes start sealed. You must unseal each node individually.

### Unseal All Nodes

```bash
# Define your nodes
NODES=("10.0.1.10" "10.0.1.11" "10.0.1.12")

for node in "${NODES[@]}"; do
  echo "Unsealing $node..."
  export VAULT_ADDR="http://${node}:8200"
  vault operator unseal  # Enter key 1
  vault operator unseal  # Enter key 2
  vault operator unseal  # Enter key 3
done
```

### Auto-Unseal (Production)

For production, configure auto-unseal using a cloud KMS:

| Provider | Configuration |
|:---------|:--------------|
| AWS KMS | `seal "awskms" { kms_key_id = "..." }` |
| GCP KMS | `seal "gcpckms" { key_ring = "..." }` |
| Azure Key Vault | `seal "azurekeyvault" { vault_name = "..." }` |
| Transit (another Vault) | `seal "transit" { address = "..." }` |

With auto-unseal, nodes unseal automatically on restart using the cloud KMS.

---

## Verifying Cluster Health

### Check Cluster Status

```bash
export VAULT_ADDR='http://10.0.1.10:8200'

# Authenticate
vault login <root-token>

# List Raft peers
vault operator raft list-peers
```

**Expected output:**
```
Node     Address              State       Voter
----     -------              -----       -----
node1    10.0.1.10:8201       leader      true
node2    10.0.1.11:8201       follower    true
node3    10.0.1.12:8201       follower    true
```

### Check Individual Node Status

```bash
# From any node
vault status

# Key fields to check:
#   Sealed: false
#   HA Enabled: true
#   HA Cluster: https://10.0.1.10:8201
#   HA Mode: standby (or active for leader)
```

---

## Key Management Best Practices

### Shamir Key Distribution

With 5 shares and threshold 3:

| Person | Keys Held |
|:-------|:----------|
| Admin 1 | Key 1, Key 2 |
| Admin 2 | Key 3, Key 4 |
| Secure Safe | Key 5 |

No single person can unseal alone. Any 2 admins together can unseal.

### Key Rotation

Periodically rotate the unseal keys:

```bash
vault operator rekey -init -key-shares=5 -key-threshold=3
# Follow prompts to provide current keys and generate new ones
```

### Root Token Revocation

After initial setup, revoke the root token and use proper policies:

```bash
# Create admin policy first
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# Enable userpass auth and create admin user
vault auth enable userpass
vault write auth/userpass/users/admin password="..." policies="admin"

# Revoke root token
vault token revoke <root-token>
```

Generate a new root token only when needed using unseal keys.

---

## Maintenance Commands

### Add a New Node

```bash
# On new node, after starting Vault:
vault operator raft join http://10.0.1.10:8200
vault operator unseal  # x3
```

### Remove a Node

```bash
# From leader
vault operator raft remove-peer node4
```

### Snapshot Backup

```bash
vault operator raft snapshot save backup.snap

# Restore (use with caution)
vault operator raft snapshot restore backup.snap
```

### Force Leader Election

```bash
# Use if leader is stuck
vault operator step-down
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--------|:------|:----|
| "Vault is sealed" | Node restarted | Unseal with 3 keys |
| Node won't join | Network/firewall | Check ports 8200, 8201 are open |
| "no known peers" | Wrong retry_join addresses | Verify IPs in config |
| Split brain | Network partition | Restore connectivity; may need to remove/rejoin node |
| Slow responses | Leader overloaded | Check resources; consider read replicas |
| "permission denied" | Token lacks policy | Use root token or add policy |

### Check Logs

```bash
# Systemd journal
sudo journalctl -u vault -f

# Or if using custom log file
tail -f /var/log/vault/vault.log
```

### Verify Network Connectivity

```bash
# From each node, verify it can reach the others
nc -zv 10.0.1.10 8200
nc -zv 10.0.1.10 8201
nc -zv 10.0.1.11 8200
# ... etc
```

---

## Quick Reference

### Ports

| Port | Purpose | Required |
|:-----|:--------|:---------|
| 8200 | API (client requests) | Yes |
| 8201 | Cluster (Raft replication) | Yes |

### Key Commands

```bash
# Status
vault status
vault operator raft list-peers

# Unseal
vault operator unseal

# Seal (emergency)
vault operator seal

# Step down leader
vault operator step-down

# Backup
vault operator raft snapshot save backup.snap
```

### Files

| File | Purpose |
|:-----|:--------|
| `/etc/vault.d/vault.hcl` | Main configuration |
| `/opt/vault/data/` | Raft data directory |
| `/etc/vault.d/vault.env` | Environment variables |

---

## Next Steps

1. **Enable TLS** - Configure certificates for production
2. **Set up policies** - Define granular access control
3. **Configure auth methods** - LDAP, OIDC, Kubernetes, etc.
4. **Enable audit logging** - Track all access
5. **Set up monitoring** - Prometheus metrics, alerting

---

## Sources

- [Vault Integrated Storage (Raft)](https://developer.hashicorp.com/vault/docs/configuration/storage/raft)
- [Vault HA Deployment Guide](https://developer.hashicorp.com/vault/tutorials/raft/raft-deployment-guide)
- [Vault Unsealing](https://developer.hashicorp.com/vault/docs/concepts/seal)
- [Shamir's Secret Sharing](https://developer.hashicorp.com/vault/docs/concepts/seal#shamir-seals)

---

*Last updated: January 2026*
