# atlas sh — Design Spec

## Overview

An Atlas CLI plugin command `atlas sh --cluster <name>` that transparently launches
`mongosh` connected to a cluster, using a cached temporary database user.

## Goals

- Minimal friction: `atlas sh --cluster prod` just works
- Reuse cached credentials across invocations (8h TTL)
- Use `mongodb-atlas-cli` crate for Atlas API access and config reading
- Store connection credentials securely in OS keychain

## Non-Goals

- Multi-cluster sessions
- Role customization (always `readWriteAnyDatabase`)
- Configurable TTL (fixed at 8h, matches a workday)
- Windows keychain support (out of scope for now)

---

## CLI Interface

```
atlas sh --cluster <cluster-name>
         [--project-id <project-id>]
         [--org-id <org-id>]
```

| Flag | Required | Description |
|------|----------|-------------|
| `--cluster` | Yes | Cluster name in the Atlas project |
| `--project-id` | No | Overrides `project_id` from Atlas CLI config |
| `--org-id` | No | Overrides `org_id` from Atlas CLI config |

Behavior: exits with a clap error if `--cluster` is not provided.
Behavior: exits with a user-friendly error if project_id is not resolvable.

---

## Module Structure

```
src/
  main.rs         — async main, orchestration logic
  args.rs         — clap argument definitions
  credentials.rs  — keyring read/write/invalidate for CachedCredentials
  atlas_ops.rs    — #[operation]-annotated Atlas Admin API operations
```

---

## Data Flow

```
atlas sh --cluster prod-cluster [--project-id <id>] [--org-id <id>]

1. Load AtlasCLIConfig via mongodb_atlas_cli::config::load_config(Some("default"))
2. Override project_id / org_id from CLI flags if provided
3. Resolve project_id — error if not set in config or flags
4. keyring.get("atlas-sh-{project_id}-{cluster}")
   ├── found + expires_at > now → skip to step 6
   └── missing or expired        → continue to step 5

5. Create temporary database user:
   a. GET /groups/{project_id}/clusters/{cluster} → extract srv_address
   b. Generate: username = "atlas-sh-{uuid}", password = random 32-char alphanumeric
   c. POST /groups/{project_id}/databaseUsers:
        { databaseName: "admin",
          username, password,
          roles: [{ roleName: "readWriteAnyDatabase", databaseName: "admin" }],
          deleteAfterDate: now + 8h (RFC3339) }
   d. Build connection_string from srv_address
   e. keyring.set("atlas-sh-{project_id}-{cluster}", CachedCredentials {
        username, password, connection_string, expires_at: now + 8h
      })

6. Resolve mongosh binary:
   a. config.mongosh_path if set
   b. else search PATH for "mongosh"
   c. else error: "mongosh not found. Install: https://www.mongodb.com/try/download/shell"

7. exec(mongosh, [connection_string, "--username", username, "--password", password])
   — replaces current process (no return)
```

---

## Data Structures

### CachedCredentials (stored as JSON in keyring)

```rust
struct CachedCredentials {
    username: String,
    password: String,
    connection_string: String,  // SRV string without credentials
    expires_at: DateTime<Utc>,
}
```

Keyring service name: `"atlas-sh"`
Keyring account key: `"{project_id}:{cluster_name}"`

### Atlas API Operations

```rust
// GET /api/atlas/v2/groups/{group_id}/clusters/{cluster_name}
// Returns: ClusterDetail { srv_address: String }
GetClusterOperation

// POST /api/atlas/v2/groups/{group_id}/databaseUsers
// Body: CreateDatabaseUserRequest { database_name, username, password, roles, delete_after_date }
// Returns: ()
CreateDatabaseUserOperation
```

---

## Error Handling

| Situation | User-facing message |
|-----------|-------------------|
| `--cluster` missing | clap usage error (automatic) |
| No project_id resolvable | `"No project ID configured. Use --project-id or run 'atlas config set project_id <id>'"` |
| Atlas API 401 | `"Authentication failed. Run 'atlas auth login' and try again."` |
| Cluster not found (404) | `"Cluster '{name}' not found in project '{project_id}'."` |
| mongosh not in PATH | `"mongosh not found. Install: https://www.mongodb.com/try/download/shell"` |
| keyring unavailable | Log warning, skip cache, always create user (degrade gracefully) |

All errors propagate via `anyhow`. User-facing output via `eprintln!` before `std::process::exit(1)`.

---

## Dependencies

New additions to `Cargo.toml`:

```toml
mongodb-atlas-cli = { version = "0.2.1", features = ["derive"] }
keyring = "4.0"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4"] }
rand = "0.8"
rustls = { version = "0.23", features = ["ring"] }
```

---

## Plugin Manifest

`manifest.template.yml` declares `sh` as the plugin's top-level command:

```yaml
name: atlas-cli-plugin-sh
description: Connect to an Atlas cluster via mongosh
version: $VERSION
github:
  owner: $GITHUB_REPOSITORY_OWNER
  name: $GITHUB_REPOSITORY_NAME
binary: $BINARY
commands:
  sh:
    description: Launch mongosh connected to an Atlas cluster
```

---

## Testing

Integration tests require Atlas credentials — out of scope for unit test suite.

Unit-testable:
- `CachedCredentials` serialization round-trip
- Keyring abstraction (mock `SecretStore` trait)
- mongosh path resolution logic
- Error message formatting

Run with `cargo test`.

---

## Out of Scope

- Deleting users on early exit (Atlas `deleteAfterDate` handles cleanup)
- `--profile` flag (always uses `"default"` profile)
- Configurable TTL
- Windows support
