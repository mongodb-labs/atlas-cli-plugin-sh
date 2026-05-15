use std::fmt;

use console::style;

#[derive(Debug)]
pub(crate) enum UserError {
    NotAuthenticated,
    ClusterNotFound {
        cluster: String,
        project_id: String,
    },
    ProjectNotConfigured,
    MongoshNotFound,
    AtlasApiError {
        action: &'static str,
        status: Option<u16>,
        detail: String,
    },
    MongoshFailed {
        exit_code: Option<i32>,
        cluster: String,
    },
    ProjectNotFound {
        project_id: String,
    },
}

impl fmt::Display for UserError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let error = style("error").red().bold();
        let hint = style("hint").yellow();
        match self {
            Self::NotAuthenticated => {
                writeln!(f, "{error}: Authentication failed")?;
                write!(f, "  {hint}: Run 'atlas auth login' and try again.")
            }
            Self::ClusterNotFound {
                cluster,
                project_id,
            } => {
                writeln!(
                    f,
                    "{error}: Cluster '{cluster}' not found in project '{project_id}'"
                )?;
                write!(
                    f,
                    "  {hint}: Check the name with \
                     'atlas clusters list --projectId {project_id}'"
                )
            }
            Self::ProjectNotConfigured => {
                writeln!(f, "{error}: No project ID configured")?;
                write!(
                    f,
                    "  {hint}: Use --project-id or run \
                     'atlas config set project_id <id>'"
                )
            }
            Self::MongoshNotFound => {
                writeln!(f, "{error}: mongosh not found")?;
                write!(
                    f,
                    "  {hint}: Install mongosh: \
                     https://www.mongodb.com/try/download/shell"
                )
            }
            Self::AtlasApiError {
                action,
                status,
                detail,
            } => {
                writeln!(f, "{error}: Atlas API error while {action}")?;
                if let Some(code) = status {
                    write!(f, "  {hint}: {detail} (HTTP {code})")
                } else {
                    write!(f, "  {hint}: {detail}")
                }
            }
            Self::MongoshFailed { exit_code, cluster } => {
                let code = exit_code.map_or_else(|| "unknown".to_owned(), |c| c.to_string());
                writeln!(f, "{error}: mongosh exited with code {code}")?;
                write!(
                    f,
                    "  {hint}: If authentication failed, run \
                     'atlas sh --cluster {cluster} --clear-cache' and try again."
                )
            }
            Self::ProjectNotFound { project_id } => {
                writeln!(f, "{error}: Project '{project_id}' not found")?;
                write!(
                    f,
                    "  {hint}: Check the project ID with 'atlas projects list'"
                )
            }
        }
    }
}

impl std::error::Error for UserError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_authenticated_contains_required_text() {
        let msg = UserError::NotAuthenticated.to_string();
        assert!(msg.contains("Authentication failed"), "got: {msg}");
        assert!(msg.contains("atlas auth login"), "got: {msg}");
    }

    #[test]
    fn cluster_not_found_includes_cluster_and_project() {
        let err = UserError::ClusterNotFound {
            cluster: "MyCluster".into(),
            project_id: "abc123".into(),
        };
        let msg = err.to_string();
        assert!(msg.contains("MyCluster"), "got: {msg}");
        assert!(msg.contains("abc123"), "got: {msg}");
        assert!(msg.contains("clusters list"), "got: {msg}");
    }

    #[test]
    fn project_not_configured_contains_required_text() {
        let msg = UserError::ProjectNotConfigured.to_string();
        assert!(msg.contains("project ID"), "got: {msg}");
        assert!(msg.contains("--project-id"), "got: {msg}");
    }

    #[test]
    fn mongosh_not_found_contains_install_hint() {
        let msg = UserError::MongoshNotFound.to_string();
        assert!(msg.contains("mongosh not found"), "got: {msg}");
        assert!(msg.contains("mongodb.com"), "got: {msg}");
    }

    #[test]
    fn atlas_api_error_includes_action_and_status() {
        let err = UserError::AtlasApiError {
            action: "fetch cluster",
            status: Some(500),
            detail: "Internal Server Error".into(),
        };
        let msg = err.to_string();
        assert!(msg.contains("fetch cluster"), "got: {msg}");
        assert!(msg.contains("500"), "got: {msg}");
        assert!(msg.contains("Internal Server Error"), "got: {msg}");
    }

    #[test]
    fn mongosh_failed_includes_exit_code_and_clear_cache_hint() {
        let err = UserError::MongoshFailed {
            exit_code: Some(1),
            cluster: "MyCluster".into(),
        };
        let msg = err.to_string();
        assert!(msg.contains("code 1"), "got: {msg}");
        assert!(msg.contains("MyCluster"), "got: {msg}");
        assert!(msg.contains("--clear-cache"), "got: {msg}");
    }

    #[test]
    fn mongosh_failed_with_unknown_exit_code() {
        let err = UserError::MongoshFailed {
            exit_code: None,
            cluster: "MyCluster".into(),
        };
        let msg = err.to_string();
        assert!(msg.contains("unknown"), "got: {msg}");
    }

    #[test]
    fn project_not_found_includes_project_id() {
        let err = UserError::ProjectNotFound {
            project_id: "abc123".into(),
        };
        let msg = err.to_string();
        assert!(msg.contains("abc123"), "got: {msg}");
        assert!(msg.contains("projects list"), "got: {msg}");
    }
}
