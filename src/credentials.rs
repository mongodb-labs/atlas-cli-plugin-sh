#[cfg(not(target_os = "macos"))]
use anyhow::anyhow;
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::domain::{ConnectionString, KeyringAccount, Password, Username};

// macOS reads/writes items through `/usr/bin/security` (Apple-signed, stable
// identity) instead of the keyring crate, so a rebuilt or re-signed binary
// doesn't re-trigger the keychain prompt. Linux/Windows keep the `keyring`
// crate's native backends.
#[cfg(target_os = "macos")]
mod security_cli;

#[cfg(not(target_os = "macos"))]
use keyring::Entry;

const KEYRING_SERVICE: &str = "atlas-sh";
pub(crate) const TTL_HOURS: i64 = 8;

// --- Per-OS secret store backend ------------------------------------------

#[cfg(target_os = "macos")]
fn get_password(service: &str, account: &str) -> Result<Option<String>> {
    security_cli::get(service, account)
}

#[cfg(not(target_os = "macos"))]
fn get_password(service: &str, account: &str) -> Result<Option<String>> {
    let entry = Entry::new(service, account).context("failed to open keyring entry")?;
    match entry.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(anyhow!("keyring error: {e}")),
    }
}

#[cfg(target_os = "macos")]
fn set_password(service: &str, account: &str, value: &str) -> Result<()> {
    security_cli::set(service, account, value)
}

#[cfg(not(target_os = "macos"))]
fn set_password(service: &str, account: &str, value: &str) -> Result<()> {
    Entry::new(service, account)
        .context("failed to open keyring entry")?
        .set_password(value)
        .map_err(|e| anyhow!("failed to write to keyring: {e}"))
}

#[cfg(target_os = "macos")]
fn delete_password(service: &str, account: &str) -> Result<bool> {
    security_cli::delete(service, account)
}

#[cfg(not(target_os = "macos"))]
fn delete_password(service: &str, account: &str) -> Result<bool> {
    let entry = Entry::new(service, account).context("failed to open keyring entry")?;
    match entry.delete_credential() {
        Ok(()) => Ok(true),
        Err(keyring::Error::NoEntry) => Ok(false),
        Err(e) => Err(anyhow!("failed to delete keyring entry: {e}")),
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct CachedCredentials {
    pub(crate) username: Username,
    pub(crate) password: Password,
    pub(crate) connection_string: ConnectionString,
    pub(crate) expires_at: DateTime<Utc>,
}

impl CachedCredentials {
    pub(crate) const fn new(
        username: Username,
        password: Password,
        connection_string: ConnectionString,
        expires_at: DateTime<Utc>,
    ) -> Self {
        Self {
            username,
            password,
            connection_string,
            expires_at,
        }
    }

    /// Whether the cached credentials should no longer be reused, given the
    /// caller's notion of "now".
    ///
    /// Treats the moment of expiry itself as expired (`now >= expires_at`):
    /// we'd rather re-issue a user one second early than send a soon-to-be
    /// invalid password to mongosh. The clock is passed in (rather than read
    /// inside this function) so the orchestration layer can inject a fake in
    /// tests via [`crate::deps::Clock`].
    pub(crate) fn is_expired_at(&self, now: DateTime<Utc>) -> bool {
        now >= self.expires_at
    }
}

fn parse_cached_json(json: &str) -> Result<CachedCredentials, serde_json::Error> {
    serde_json::from_str(json)
}

/// Load cached credentials from the OS keychain.
///
/// - `Ok(Some(creds))` when an entry exists and parses cleanly.
/// - `Ok(None)` when no entry exists for `account`, or when the cached JSON is
///   corrupt (prints a warning and treats as a miss — not an error).
/// - `Err(_)` when the keyring is unavailable (`DBus` down, permission denied, …).
///
/// All keyring failures collapse into `anyhow::Error`. The only consumer is
/// `main`, which degrades gracefully on any error by re-provisioning a user.
pub(crate) fn load(account: &KeyringAccount) -> Result<Option<CachedCredentials>> {
    get_password(KEYRING_SERVICE, account.as_str())?.map_or_else(
        || Ok(None),
        |json| match parse_cached_json(&json) {
            Ok(creds) => Ok(Some(creds)),
            Err(e) => {
                tracing::warn!(%e, "corrupted cached credentials, treating as cache miss");
                eprintln!(
                    "{}: Cached credentials corrupted \u{2014} creating new user.",
                    console::style("warning").yellow().bold()
                );
                Ok(None)
            }
        },
    )
}

/// Store credentials in the OS keychain.
pub(crate) fn store(account: &KeyringAccount, creds: &CachedCredentials) -> Result<()> {
    let json = serde_json::to_string(creds).context("failed to serialize credentials")?;
    set_password(KEYRING_SERVICE, account.as_str(), &json)
}

/// Delete cached credentials from the OS keychain.
///
/// Returns `Ok(true)` when an entry was removed and `Ok(false)` when nothing
/// was cached for `account` (idempotent — calling logout twice is not an
/// error). Returns `Err` for genuine keyring failures.
pub(crate) fn invalidate(account: &KeyringAccount) -> Result<bool> {
    delete_password(KEYRING_SERVICE, account.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{ClusterName, ProjectId};

    fn fresh_creds() -> CachedCredentials {
        CachedCredentials::new(
            Username::new("atlas-sh-user"),
            Password::new("super-secret"),
            ConnectionString::new("mongodb+srv://cluster.abc.mongodb.net"),
            Utc::now() + chrono::Duration::hours(TTL_HOURS),
        )
    }

    #[test]
    fn round_trips_through_json() {
        let creds = fresh_creds();
        let json = serde_json::to_string(&creds).unwrap();

        // Password must appear in the serialized form (keyring storage).
        assert!(json.contains("super-secret"), "password must serialize");
        assert!(json.contains("atlas-sh-user"));
        assert!(json.contains("mongodb+srv"));

        let decoded: CachedCredentials = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.username.as_str(), "atlas-sh-user");
        assert_eq!(decoded.password.as_str(), "super-secret");
        assert_eq!(
            decoded.connection_string.as_str(),
            "mongodb+srv://cluster.abc.mongodb.net"
        );
    }

    #[test]
    fn debug_redacts_secrets() {
        let creds = fresh_creds();
        let debug = format!("{creds:?}");
        assert!(
            !debug.contains("super-secret"),
            "password must not appear in Debug",
        );
        assert!(
            !debug.contains("mongodb+srv"),
            "connection string must not appear in Debug",
        );
        assert!(debug.contains("REDACTED"));
    }

    #[test]
    fn is_expired_at_boundary_is_inclusive() {
        let mut creds = fresh_creds();
        let pinned = chrono::DateTime::parse_from_rfc3339("2026-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        creds.expires_at = pinned;

        // One nanosecond before: not expired.
        assert!(!creds.is_expired_at(pinned - chrono::Duration::nanoseconds(1)));
        // Exactly at expiry: expired (inclusive `>=`).
        assert!(creds.is_expired_at(pinned));
        // One nanosecond after: expired.
        assert!(creds.is_expired_at(pinned + chrono::Duration::nanoseconds(1)));
    }

    #[test]
    fn keyring_account_passes_through_to_underlying_apis() {
        let account = KeyringAccount::new(&ProjectId::new("p"), &ClusterName::new("c"));
        // We cannot exercise the real keyring in unit tests without flakiness
        // on different platforms; the assertion documents the format the
        // keyring sees.
        assert_eq!(account.as_str(), "p:c");
    }

    #[test]
    fn parse_cached_json_returns_err_for_corrupt_input() {
        assert!(parse_cached_json("this is not json").is_err());
    }

    #[test]
    fn parse_cached_json_returns_creds_for_valid_json() {
        let creds = fresh_creds();
        let json = serde_json::to_string(&creds).unwrap();
        let result = parse_cached_json(&json);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().username.as_str(), "atlas-sh-user");
    }
}
