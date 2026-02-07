import Foundation

/// Represents the detected source type for the input
enum InputSource: CustomStringConvertible, Equatable {
    /// Jira ticket (e.g., "IOS-1234")
    case jira(String)

    /// GitHub issue number (e.g., "567"), with optional repo from URL
    case github(String, repo: String?)

    /// GitHub pull request number (e.g., "567"), with optional repo from URL
    case githubPR(String, repo: String?)

    /// Raw prompt text
    case rawPrompt(String)

    var description: String {
        switch self {
        case .jira(let id):
            return "Jira(\(id))"
        case .github(let number, let repo):
            if let repo = repo {
                return "GitHub(\(repo)#\(number))"
            }
            return "GitHub(#\(number))"
        case .githubPR(let number, let repo):
            if let repo = repo {
                return "GitHubPR(\(repo)#\(number))"
            }
            return "GitHubPR(#\(number))"
        case .rawPrompt(let prompt):
            let truncated = prompt.prefix(30)
            return "RawPrompt(\"\(truncated)...\")"
        }
    }
}
