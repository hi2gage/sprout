import ArgumentParser
import Foundation

@main
struct Sprout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sprout",
        abstract: "Create git worktrees and launch Claude Code with context from various sources.",
        version: "0.1.0",
        subcommands: [Launch.self, List.self, Prune.self],
        defaultSubcommand: Launch.self
    )
}

/// Errors from source fetching
enum SourceError: Error, CustomStringConvertible {
    case jiraNotConfigured
    case githubNotConfigured
    case authFailed(String)
    case ticketNotFound(String)
    case networkError(Error)
    case repoMismatch(expected: String, actual: String)

    var description: String {
        switch self {
        case .jiraNotConfigured:
            return "Jira source requested but not configured in config file"
        case .githubNotConfigured:
            return "GitHub source requested but not configured in config file"
        case .authFailed(let source):
            return "Authentication failed for \(source)"
        case .ticketNotFound(let id):
            return "Ticket not found: \(id)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .repoMismatch(let expected, let actual):
            return "Repository mismatch: URL is for '\(expected)' but you're in '\(actual)'"
        }
    }

    var exitCode: Int32 {
        2 // Source error
    }
}

/// Errors from git operations
enum GitError: Error, CustomStringConvertible {
    case notInRepo
    case worktreeCreationFailed(String)
    case commandFailed(String, String)

    var description: String {
        switch self {
        case .notInRepo:
            return "Not in a git repository"
        case .worktreeCreationFailed(let message):
            return "Failed to create worktree: \(message)"
        case .commandFailed(let command, let message):
            return "Git command '\(command)' failed: \(message)"
        }
    }

    var exitCode: Int32 {
        3 // Git error
    }
}

/// Errors from script execution
enum ScriptError: Error, CustomStringConvertible {
    case executionFailed(Int)

    var description: String {
        switch self {
        case .executionFailed(let code):
            return "Launch script failed with exit code \(code)"
        }
    }

    var exitCode: Int32 {
        4 // Script error
    }
}
