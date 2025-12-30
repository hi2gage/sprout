import ArgumentParser
import Foundation

@main
struct Sprout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sprout",
        abstract: "Create git worktrees and launch Claude Code with context from various sources.",
        version: "0.1.0"
    )

    // MARK: - Arguments

    @Argument(help: "Input: Jira ticket (IOS-1234), GitHub issue (#567), or raw prompt text")
    var input: String

    // MARK: - Explicit Source Flags

    @Option(name: [.short, .customLong("jira")], help: "Explicitly use Jira source with this ticket ID")
    var jiraTicket: String?

    @Option(name: [.short, .customLong("github")], help: "Explicitly use GitHub source with this issue number")
    var githubIssue: String?

    @Option(name: [.short, .customLong("prompt")], help: "Explicitly use raw prompt")
    var rawPrompt: String?

    // MARK: - Options

    @Option(name: [.short, .long], help: "Override branch name")
    var branch: String?

    @Option(name: [.short, .long], help: "Use alternate config file")
    var config: String?

    // MARK: - Flags

    @Flag(name: [.short, .customLong("dry-run")], help: "Print what would be executed without running")
    var dryRun: Bool = false

    @Flag(name: [.short, .long], help: "Print detailed output")
    var verbose: Bool = false

    // MARK: - Run

    func run() async throws {
        // Load configuration
        let configPath = config ?? ConfigLoader.defaultConfigPath
        let sproutConfig: SproutConfig

        do {
            sproutConfig = try ConfigLoader.load(from: configPath)
        } catch let error as ConfigError {
            printError(error.description)
            throw ExitCode(error.exitCode)
        }

        if verbose {
            print("Loaded config from: \(configPath)")
        }

        // Determine input source
        let source = try detectInputSource()

        if verbose {
            print("Detected source: \(source)")
        }

        // Fetch context from source
        let context = try await fetchContext(for: source, config: sproutConfig)

        if verbose {
            print("Fetched context: \(context.title ?? "raw prompt")")
        }

        // Compute variables
        let variables = try await buildVariables(context: context, config: sproutConfig)

        if verbose {
            print("Variables: \(variables)")
        }

        // Compose and write prompt file
        let promptFile = try composePrompt(context: context, config: sproutConfig, variables: variables)

        if verbose {
            print("Wrote prompt to: \(promptFile)")
        }

        // Interpolate and execute launch script
        let script = interpolate(sproutConfig.launch.script, with: variables.merging(["prompt_file": promptFile]) { _, new in new })

        if dryRun {
            print("Would execute:")
            print("---")
            print(script)
            print("---")
            return
        }

        try await executeScript(script)
    }

    // MARK: - Input Detection

    private func detectInputSource() throws -> InputSource {
        // Explicit flags take precedence
        if let jira = jiraTicket {
            return .jira(jira)
        }
        if let github = githubIssue {
            return .github(github, repo: nil)
        }
        if let prompt = rawPrompt {
            return .rawPrompt(prompt)
        }

        // Auto-detect from input
        return InputDetector.detect(input)
    }

    // MARK: - Context Fetching

    private func fetchContext(for source: InputSource, config: SproutConfig) async throws -> TicketContext {
        switch source {
        case .jira(let ticketId):
            guard let jiraConfig = config.sources?.jira else {
                throw SourceError.jiraNotConfigured
            }
            let client = JiraClient(config: jiraConfig)
            return try await client.fetchTicket(ticketId)

        case .github(let issueNumber, let urlRepo):
            // If repo was extracted from URL, validate it matches current repo
            if let urlRepo = urlRepo {
                let gitService = GitService()
                if let currentRepo = try await gitService.getRemoteRepo() {
                    if currentRepo.lowercased() != urlRepo.lowercased() {
                        throw SourceError.repoMismatch(expected: urlRepo, actual: currentRepo)
                    }
                }
            }

            guard let githubConfig = config.sources?.github else {
                throw SourceError.githubNotConfigured
            }
            let client = GitHubClient(config: githubConfig)
            return try await client.fetchIssue(issueNumber)

        case .rawPrompt(let prompt):
            return TicketContext.fromRawPrompt(prompt)
        }
    }

    // MARK: - Variable Building

    private func buildVariables(context: TicketContext, config: SproutConfig) async throws -> [String: String] {
        let gitService = GitService()
        let repoRoot = try await gitService.getRepoRoot()

        // Compute branch name
        let branchTemplate = config.worktree?.resolvedBranchTemplate ?? "{ticket_id}"
        let branchName = self.branch ?? interpolate(branchTemplate, with: [
            "ticket_id": context.ticketId,
            "slug": context.slug ?? Slugify.slugify(context.title ?? context.ticketId),
            "user": config.variables?["user"] ?? "",
        ])

        // Compute worktree path
        let pathTemplate = config.worktree?.resolvedPathTemplate ?? "../worktrees/{branch}"
        let worktreePath = interpolate(pathTemplate, with: ["branch": branchName])
        let absoluteWorktreePath: String
        if worktreePath.hasPrefix("/") {
            absoluteWorktreePath = worktreePath
        } else {
            absoluteWorktreePath = URL(fileURLWithPath: repoRoot)
                .appendingPathComponent(worktreePath)
                .standardized
                .path
        }

        // Build variable dictionary
        var variables: [String: String] = [
            "ticket_id": context.ticketId,
            "branch": branchName,
            "worktree": absoluteWorktreePath,
            "repo_root": repoRoot,
            "timestamp": String(Int(Date().timeIntervalSince1970)),
            "date": ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withDashSeparatorInDate]),
        ]

        // Add ticket-specific variables
        if let title = context.title {
            variables["title"] = title
        }
        if let description = context.description {
            variables["description"] = description
        }
        if let slug = context.slug {
            variables["slug"] = slug
        }
        if let url = context.url {
            variables["url"] = url
        }
        if let author = context.author {
            variables["author"] = author
        }
        if let labels = context.labels {
            variables["labels"] = labels.joined(separator: ", ")
        }

        // Merge custom variables from config
        if let customVars = config.variables {
            for (key, value) in customVars {
                variables[key] = value
            }
        }

        return variables
    }

    // MARK: - Prompt Composition

    private func composePrompt(context: TicketContext, config: SproutConfig, variables: [String: String]) throws -> String {
        let composer = PromptComposer(config: config.prompt)
        return try composer.compose(context: context, variables: variables)
    }

    // MARK: - Script Execution

    private func executeScript(_ script: String) async throws {
        let runner = ScriptRunner()
        try await runner.execute(script, verbose: verbose)
    }

    // MARK: - Helpers

    private func interpolate(_ template: String, with variables: [String: String]) -> String {
        Interpolation.interpolate(template, with: variables)
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    }
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
    case commandFailed(String, Int)

    var description: String {
        switch self {
        case .notInRepo:
            return "Not in a git repository"
        case .worktreeCreationFailed(let message):
            return "Failed to create worktree: \(message)"
        case .commandFailed(let command, let code):
            return "Git command failed (\(code)): \(command)"
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
