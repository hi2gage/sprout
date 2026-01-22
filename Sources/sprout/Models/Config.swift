import Foundation

/// Root configuration loaded from ~/.sprout/config.toml
struct SproutConfig: Codable {
    var worktree: WorktreeConfig?
    var prompt: PromptConfig?
    var launch: LaunchConfig
    var sources: SourcesConfig?
    var detection: DetectionConfig?
    var variables: [String: String]?

    init(
        worktree: WorktreeConfig? = nil,
        prompt: PromptConfig? = nil,
        launch: LaunchConfig,
        sources: SourcesConfig? = nil,
        detection: DetectionConfig? = nil,
        variables: [String: String]? = nil
    ) {
        self.worktree = worktree
        self.prompt = prompt
        self.launch = launch
        self.sources = sources
        self.detection = detection
        self.variables = variables
    }
}

/// Worktree path and branch naming configuration
struct WorktreeConfig: Codable {
    /// Where to create worktrees (relative to repo root, or absolute path)
    /// Default: "../worktrees/{branch}"
    var pathTemplate: String?

    /// Branch naming template
    /// Default: "{ticket_id}"
    var branchTemplate: String?

    enum CodingKeys: String, CodingKey {
        case pathTemplate = "path_template"
        case branchTemplate = "branch_template"
    }

    var resolvedPathTemplate: String {
        pathTemplate ?? "../worktrees/{branch}"
    }

    var resolvedBranchTemplate: String {
        branchTemplate ?? "{ticket_id}"
    }
}

/// Prompt composition configuration
struct PromptConfig: Codable {
    /// Prefix added before ticket content
    var prefix: String?

    /// Template for composing the prompt body
    /// Default: "# {title}\n\n{description}"
    var template: String?

    /// Suffix added after ticket content
    var suffix: String?

    var resolvedTemplate: String {
        template ?? "# {title}\n\n{description}"
    }
}

/// Launch script configuration
struct LaunchConfig: Codable {
    /// Shell script executed after worktree creation (for new tickets)
    var script: String

    /// Shell script for PRs (defaults to script if not set)
    var prScript: String?

    enum CodingKeys: String, CodingKey {
        case script
        case prScript = "pr_script"
    }

    /// Get the appropriate script for PRs
    var resolvedPRScript: String {
        prScript ?? script
    }
}

/// Source-specific configurations
struct SourcesConfig: Codable {
    var jira: JiraConfig?
    var github: GitHubConfig?
}

/// Jira API configuration
struct JiraConfig: Codable {
    /// Base URL for Jira instance (e.g., "https://yourcompany.atlassian.net")
    var baseUrl: String

    /// Email address for authentication
    var email: String

    /// API token (optional - prefer JIRA_API_TOKEN env var)
    var token: String?

    /// Default project key for auto-detection
    var defaultProject: String?

    /// Fields to include in prompt
    var fields: [String]?

    enum CodingKeys: String, CodingKey {
        case baseUrl = "base_url"
        case email
        case token
        case defaultProject = "default_project"
        case fields
    }

    var resolvedFields: [String] {
        fields ?? ["summary", "description"]
    }
}

/// GitHub API configuration
struct GitHubConfig: Codable {
    /// Default repo for issue lookup (e.g., "org/repo-name")
    var repo: String?

    /// API token (optional - prefer GITHUB_TOKEN env var)
    var token: String?
}

/// Detection patterns for auto-detecting input type
struct DetectionConfig: Codable {
    /// Regex pattern for Jira tickets
    /// Default: "[A-Z]+-[0-9]+"
    var jiraPattern: String?

    /// Patterns for GitHub issues
    /// Default: ["#[0-9]+", "gh:[0-9]+"]
    var githubPatterns: [String]?

    enum CodingKeys: String, CodingKey {
        case jiraPattern = "jira_pattern"
        case githubPatterns = "github_patterns"
    }

    var resolvedJiraPattern: String {
        jiraPattern ?? "[A-Z]+-[0-9]+"
    }

    var resolvedGitHubPatterns: [String] {
        githubPatterns ?? ["#[0-9]+", "gh:[0-9]+"]
    }
}
