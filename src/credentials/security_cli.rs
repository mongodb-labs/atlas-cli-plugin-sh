//! macOS secret store backend that drives `/usr/bin/security`, the same
//! approach zalando/go-keyring uses for the official Atlas CLI.
//!
//! Why not the native Security.framework API (via the `keyring` crate): the
//! legacy keychain ACL trusts the *application that created an item*, keyed on
//! the binary's identity. For our Developer ID-signed release binary that
//! identity is stable *per build* in practice the prompt re-appears on every
//! rebuild/release. Items created through `security` trust `/usr/bin/security`
//! (Apple-signed, stable), so a rebuilt plugin never re-prompts.

use std::io::Write;
use std::process::{Command, Output, Stdio};

use anyhow::{anyhow, Context, Result};

const SECURITY_BIN: &str = "/usr/bin/security";
const NOT_FOUND_MARKER: &str = "could not be found";
/// Same per-command limit go-keyring enforces for `security -i`.
const MAX_COMMAND_LEN: usize = 4096;

pub(crate) fn get(service: &str, account: &str) -> Result<Option<String>> {
    let output = Command::new(SECURITY_BIN)
        .args(["find-generic-password", "-s", service, "-wa", account])
        .output()
        .map_err(|e| io_error(&e))?;
    parse_find_output(&output)
}

pub(crate) fn set(service: &str, account: &str, value: &str) -> Result<()> {
    // Interactive mode keeps the secret out of argv (and thus out of `ps`).
    let command = build_add_command(service, account, value)?;
    let mut child = Command::new(SECURITY_BIN)
        .arg("-i")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| io_error(&e))?;
    let mut stdin = child
        .stdin
        .take()
        .context("security did not expose stdin")?;
    // Write first, then reap. If `security` exits early the write hits EPIPE;
    // we still reap so its stderr (the only explanation) is kept and we don't
    // leave a zombie.
    let write_result = stdin.write_all(command.as_bytes());
    drop(stdin);
    let output = child.wait_with_output().map_err(|e| io_error(&e))?;
    if !output.status.success() {
        return Err(unavailable(&output));
    }
    write_result.map_err(|e| io_error(&e))
}

pub(crate) fn delete(service: &str, account: &str) -> Result<bool> {
    let output = Command::new(SECURITY_BIN)
        .args(["delete-generic-password", "-s", service, "-a", account])
        .output()
        .map_err(|e| io_error(&e))?;
    if is_not_found(&output) {
        Ok(false)
    } else if output.status.success() {
        Ok(true)
    } else {
        Err(unavailable(&output))
    }
}

fn parse_find_output(output: &Output) -> Result<Option<String>> {
    if is_not_found(output) {
        return Ok(None);
    }
    if !output.status.success() {
        return Err(unavailable(output));
    }
    // Strict decode: a lossy conversion would hand a silently mangled secret
    // to the caller.
    let value = String::from_utf8(output.stdout.clone())
        .map_err(|e| anyhow!("secret is not valid UTF-8: {e}"))?;
    Ok(Some(value.trim().to_string()))
}

fn build_add_command(service: &str, account: &str, value: &str) -> Result<String> {
    // `security -i` splits input into commands on line breaks *before* quote
    // parsing, so a `'` cannot neutralise an embedded newline: it would
    // terminate this command and execute the remainder as a new one.
    if [service, account, value]
        .iter()
        .any(|s| contains_line_break(s))
    {
        return Err(anyhow!(
            "service, account and secret must not contain line breaks"
        ));
    }
    let command = format!(
        "add-generic-password -U -s {} -a {} -w {}\n",
        quote(service),
        quote(account),
        quote(value)
    );
    if command.len() > MAX_COMMAND_LEN {
        return Err(anyhow!(
            "secret command is {} bytes, over the {MAX_COMMAND_LEN}-byte limit",
            command.len()
        ));
    }
    Ok(command)
}

fn contains_line_break(s: &str) -> bool {
    s.contains(['\n', '\r'])
}

/// Quote a token for `security -i`; mirrors go-keyring's shellescape.Quote.
fn quote(s: &str) -> String {
    if s.is_empty() {
        return "''".to_string();
    }
    let is_safe = |c: char| c.is_ascii_alphanumeric() || "_@%+=:,./-".contains(c);
    if s.chars().all(is_safe) {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

fn is_not_found(output: &Output) -> bool {
    !output.status.success() && String::from_utf8_lossy(&output.stderr).contains(NOT_FOUND_MARKER)
}

fn unavailable(output: &Output) -> anyhow::Error {
    anyhow!(
        "security exited with {}: {}",
        output.status,
        String::from_utf8_lossy(&output.stderr).trim()
    )
}

fn io_error(e: &std::io::Error) -> anyhow::Error {
    anyhow!("failed to run {SECURITY_BIN}: {e}")
}

#[cfg(test)]
mod tests {
    use std::process::ExitStatus;

    use super::*;

    #[cfg(unix)]
    fn exit_status(code: i32) -> ExitStatus {
        use std::os::unix::process::ExitStatusExt;
        ExitStatus::from_raw(code << 8)
    }

    #[cfg(windows)]
    fn exit_status(code: i32) -> ExitStatus {
        use std::os::windows::process::ExitStatusExt;
        ExitStatus::from_raw(code as u32)
    }

    fn output(code: i32, stdout: &str, stderr: &str) -> Output {
        Output {
            status: exit_status(code),
            stdout: stdout.as_bytes().to_vec(),
            stderr: stderr.as_bytes().to_vec(),
        }
    }

    #[test]
    fn parse_find_output_returns_trimmed_value() {
        let parsed = parse_find_output(&output(0, "atlas-sh-json\n", "")).unwrap();
        assert_eq!(parsed, Some("atlas-sh-json".to_string()));
    }

    #[test]
    fn parse_find_output_returns_none_when_item_missing() {
        let stderr = "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.\n";
        let parsed = parse_find_output(&output(44, "", stderr)).unwrap();
        assert_eq!(parsed, None);
    }

    #[test]
    fn parse_find_output_is_err_on_other_failure() {
        let err = parse_find_output(&output(51, "", "User interaction is not allowed."))
            .unwrap_err()
            .to_string();
        assert!(err.contains("User interaction"));
    }

    #[test]
    fn parse_find_output_rejects_invalid_utf8() {
        let raw = Output {
            status: exit_status(0),
            stdout: vec![0xff, 0xfe, b'\n'],
            stderr: Vec::new(),
        };
        let err = parse_find_output(&raw).unwrap_err().to_string();
        assert!(err.contains("UTF-8"));
    }

    #[test]
    fn is_not_found_requires_failure_exit_status() {
        assert!(!is_not_found(&output(0, "", "could not be found")));
        assert!(is_not_found(&output(44, "", "could not be found")));
    }

    #[test]
    fn add_command_leaves_safe_tokens_unquoted() {
        let cmd = build_add_command("atlas-sh", "p:c", "JSON").unwrap();
        assert_eq!(cmd, "add-generic-password -U -s atlas-sh -a p:c -w JSON\n");
    }

    #[test]
    fn add_command_quotes_unsafe_tokens() {
        let cmd = build_add_command("atlas-sh", "it's", "a b $x").unwrap();
        assert_eq!(
            cmd,
            "add-generic-password -U -s atlas-sh -a 'it'\"'\"'s' -w 'a b $x'\n"
        );
    }

    #[test]
    fn add_command_rejects_newline_injection() {
        let err = build_add_command("atlas-sh\ndelete-generic-password -s x", "a", "v")
            .unwrap_err()
            .to_string();
        assert!(err.contains("line breaks"));
    }

    #[test]
    fn add_command_rejects_over_limit() {
        let value = "x".repeat(MAX_COMMAND_LEN + 1);
        let err = build_add_command("s", "a", &value).unwrap_err().to_string();
        assert!(err.contains("limit"));
    }

    #[test]
    fn ad_hoc_quote_empty_string_is_quoted() {
        assert_eq!(quote(""), "''");
    }

    #[test]
    fn quote_escapes_single_quotes_like_go_keyring() {
        assert_eq!(quote("it's"), "'it'\"'\"'s'");
    }
}
