import Foundation

/// Detects the input source type from user input
struct InputDetector {
    /// Detect the input source from the given string
    static func detect(_ input: String) -> InputSource {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for Jira URL pattern
        // e.g., https://company.atlassian.net/browse/IOS-1234
        if let jiraId = extractJiraFromURL(trimmed) {
            return .jira(jiraId)
        }

        // Check for GitHub PR URL pattern first (before issues)
        // e.g., https://github.com/org/repo/pull/567
        if let (prNumber, repo) = extractGitHubPRFromURL(trimmed) {
            return .githubPR(prNumber, repo: repo)
        }

        // Check for GitHub issue URL pattern
        // e.g., https://github.com/org/repo/issues/567
        if let (issueNumber, repo) = extractGitHubIssueFromURL(trimmed) {
            return .github(issueNumber, repo: repo)
        }

        // Check for Jira ticket pattern: ABC-123
        if let match = trimmed.wholeMatch(of: /^([A-Z]+-[0-9]+)$/) {
            return .jira(String(match.1))
        }

        // Check for GitHub PR shorthand pattern: pr:567
        if let match = trimmed.wholeMatch(of: /^(?i)pr:(\d+)$/) {
            return .githubPR(String(match.1), repo: nil)
        }

        // Check for GitHub issue shorthand patterns: #567 or gh:567
        if let match = trimmed.wholeMatch(of: /^#(\d+)$/) {
            return .github(String(match.1), repo: nil)
        }
        if let match = trimmed.wholeMatch(of: /^(?i)gh:(\d+)$/) {
            return .github(String(match.1), repo: nil)
        }

        // Default to raw prompt
        return .rawPrompt(trimmed)
    }

    /// Extract Jira ticket ID from a Jira URL
    private static func extractJiraFromURL(_ url: String) -> String? {
        // Pattern: atlassian.net/browse/ABC-123
        let pattern = /atlassian\.net\/browse\/([A-Z]+-[0-9]+)/
        guard let match = url.firstMatch(of: pattern) else {
            return nil
        }
        return String(match.1)
    }

    /// Extract GitHub issue number and repo from a GitHub URL
    /// Returns (issueNumber, "owner/repo")
    private static func extractGitHubIssueFromURL(_ url: String) -> (String, String)? {
        // Pattern: github.com/owner/repo/issues/123
        let pattern = /github\.com\/([^\/]+\/[^\/]+)\/issues\/(\d+)/
        guard let match = url.firstMatch(of: pattern) else {
            return nil
        }
        return (String(match.2), String(match.1))
    }

    /// Extract GitHub PR number and repo from a GitHub URL
    /// Returns (prNumber, "owner/repo")
    private static func extractGitHubPRFromURL(_ url: String) -> (String, String)? {
        // Pattern: github.com/owner/repo/pull/123
        let pattern = /github\.com\/([^\/]+\/[^\/]+)\/pull\/(\d+)/
        guard let match = url.firstMatch(of: pattern) else {
            return nil
        }
        return (String(match.2), String(match.1))
    }
}
