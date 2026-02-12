import ArgumentParser
import Foundation

struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Create a worktree and launch Claude Code with context from a ticket or prompt"
    )

    // MARK: - Arguments

    @Argument(help: "Input: Jira ticket (IOS-1234), GitHub issue (#567), URL, or raw prompt text")
    var input: String

    // MARK: - Explicit Source Flags

    @Option(name: [.short, .customLong("jira")], help: "Explicitly use Jira source with this ticket ID")
    var jiraTicket: String?

    @Option(name: [.short, .customLong("github")], help: "Explicitly use GitHub source with this issue number")
    var githubIssue: String?

    @Option(name: [.short, .customLong("prompt")], help: "Explicitly use raw prompt")
    var rawPrompt: String?

    @Option(name: [.customLong("pr")], help: "Explicitly use GitHub PR number")
    var githubPR: String?

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

        // Check for comma-separated inputs (batch mode)
        if input.contains(",") {
            let tickets = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if verbose {
                print("Batch mode: \(tickets.count) tickets")
            }
            for (index, ticket) in tickets.enumerated() {
                if verbose {
                    print("[\(index + 1)/\(tickets.count)] Processing: \(ticket)")
                }
                try await launchSingle(ticket, config: sproutConfig)
                // Small delay between launches so iTerm windows don't collide
                if index < tickets.count - 1 {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                }
            }
            return
        }

        // Single input mode
        try await launchSingle(input, config: sproutConfig)
    }

    // MARK: - Single Launch

    private func launchSingle(_ inputString: String, config sproutConfig: SproutConfig) async throws {
        // Determine input source
        let source = detectInputSource(from: inputString)

        if verbose {
            print("Detected source: \(source)")
        }

        // Fetch context from source
        let context = try await fetchContext(for: source, config: sproutConfig)

        if verbose {
            print("Fetched context: \(context.title ?? "raw prompt")")
        }

        // Compute variables
        var variables = try await buildVariables(context: context, config: sproutConfig)

        if verbose {
            print("Variables:")
            for key in variables.keys.sorted() {
                let value = variables[key]!
                // Truncate long values for display
                let displayValue = value.count > 80 ? String(value.prefix(77)) + "..." : value
                print("  \(key): \(displayValue)")
            }
        }

        // Ensure worktree exists (create if needed)
        let worktreePath = variables["worktree"]!
        let branchName = variables["branch"]!
        let worktreeExists = try await ensureWorktreeExists(
            at: worktreePath,
            branch: branchName,
            hasPRBranch: context.sourceBranch != nil,
            dryRun: dryRun
        )
        variables["worktree_created"] = worktreeExists ? "false" : "true"

        // Determine which script to use (PR vs regular ticket)
        let isPR = context.sourceBranch != nil
        let launchScript = isPR ? sproutConfig.launch.resolvedPRScript : sproutConfig.launch.script

        // Compose prompt content (for non-PR sources)
        if !isPR {
            let promptContent = composePromptContent(context: context, config: sproutConfig, variables: variables)

            // Escape prompt for AppleScript/shell use
            let escapedPrompt = promptContent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "'", with: "'\\''")  // Escape single quotes for osascript -e '...'
                .replacingOccurrences(of: "\n", with: "\\n")
            variables["prompt"] = escapedPrompt

            // Only write prompt file if the script uses {prompt_file}
            if launchScript.contains("{prompt_file}") {
                let promptFile = try writePromptFile(promptContent, variables: variables)
                variables["prompt_file"] = promptFile
                if verbose {
                    print("Wrote prompt to: \(promptFile)")
                }
            }
        }

        // Interpolate and execute launch script
        let script = interpolate(launchScript, with: variables)

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

    private func detectInputSource(from inputString: String) -> InputSource {
        // Explicit flags take precedence (only for single input mode)
        if let jira = jiraTicket {
            return .jira(jira)
        }
        if let github = githubIssue {
            return .github(github, repo: nil)
        }
        if let pr = githubPR {
            return .githubPR(pr, repo: nil)
        }
        if let prompt = rawPrompt {
            return .rawPrompt(prompt)
        }

        // Auto-detect from input
        return InputDetector.detect(inputString)
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
            let repo = try await resolveGitHubRepo(urlRepo: urlRepo, config: config)
            let client = GitHubClient(repo: repo)
            return try await client.fetchIssue(issueNumber)

        case .githubPR(let prNumber, let urlRepo):
            let repo = try await resolveGitHubRepo(urlRepo: urlRepo, config: config)
            let client = GitHubClient(repo: repo)
            return try await client.fetchPR(prNumber)

        case .rawPrompt(let prompt):
            return TicketContext.fromRawPrompt(prompt)
        }
    }

    /// Resolve the GitHub repo to use - from URL, config, or current git remote
    private func resolveGitHubRepo(urlRepo: String?, config: SproutConfig) async throws -> String {
        // If repo was extracted from URL, validate it matches current repo
        if let urlRepo = urlRepo {
            let gitService = GitService()
            if let currentRepo = try await gitService.getRemoteRepo() {
                if currentRepo.lowercased() != urlRepo.lowercased() {
                    throw SourceError.repoMismatch(expected: urlRepo, actual: currentRepo)
                }
            }
            return urlRepo
        }

        // Try config repo
        if let configRepo = config.sources?.github?.repo {
            return configRepo
        }

        // Try to get repo from current git remote
        let gitService = GitService()
        if let remoteRepo = try await gitService.getRemoteRepo() {
            return remoteRepo
        }

        throw SourceError.githubNotConfigured
    }

    // MARK: - Variable Building

    private func buildVariables(context: TicketContext, config: SproutConfig) async throws -> [String: String] {
        let gitService = GitService()
        let repoRoot = try await gitService.getRepoRoot()

        // Extract repo name from path (e.g., "FreshWall" from "/Users/gage/Dev/Startups/FreshWall")
        let repoName = URL(fileURLWithPath: repoRoot).lastPathComponent

        // Compute branch name:
        // 1. Explicit --branch flag takes priority
        // 2. For PRs, use the PR's source branch
        // 3. Otherwise, use the branch template
        let branchName: String
        if let explicitBranch = self.branch {
            branchName = explicitBranch
        } else if let sourceBranch = context.sourceBranch {
            // PRs already have a branch - use it
            branchName = sourceBranch
        } else {
            let branchTemplate = config.worktree?.resolvedBranchTemplate ?? "{ticket_id}"
            branchName = interpolate(branchTemplate, with: [
                "ticket_id": context.ticketId,
                "slug": context.slug ?? Slugify.slugify(context.title ?? context.ticketId),
                "user": config.variables?["user"] ?? "",
            ])
        }

        // Compute worktree path - sanitize branch name to avoid nested directories
        let sanitizedBranchForPath = branchName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let pathTemplate = config.worktree?.resolvedPathTemplate ?? "../worktrees/{branch}"
        let worktreePath = interpolate(pathTemplate, with: [
            "branch": sanitizedBranchForPath,
            "repo_name": repoName,
        ])
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
            "repo_name": repoName,
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

    private func composePromptContent(context: TicketContext, config: SproutConfig, variables: [String: String]) -> String {
        let composer = PromptComposer(config: config.prompt)
        return composer.composeContent(context: context, variables: variables)
    }

    private func writePromptFile(_ content: String, variables: [String: String]) throws -> String {
        let promptsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sprout")
            .appendingPathComponent("prompts")

        try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)

        let branch = variables["branch"] ?? "prompt"
        let sanitizedBranch = branch
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let filename = "\(sanitizedBranch).md"
        let promptFile = promptsDir.appendingPathComponent(filename)

        try content.write(to: promptFile, atomically: true, encoding: .utf8)
        return promptFile.path
    }

    // MARK: - Worktree Management

    /// Ensure a worktree exists at the given path, creating it if needed.
    /// Returns true if worktree already existed, false if it was created.
    private func ensureWorktreeExists(at path: String, branch: String, hasPRBranch: Bool, dryRun: Bool) async throws -> Bool {
        let gitService = GitService()

        // Prune stale worktree references before checking
        try await gitService.pruneWorktrees()

        // Check if worktree already exists at this path
        let existingWorktrees = try await gitService.listWorktrees()
        if existingWorktrees.contains(where: { $0.path == path }) {
            if verbose {
                print("Worktree already exists at \(path)")
            }
            return true
        }

        // Ensure parent directory exists
        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: parentDir) {
            if dryRun {
                print("Would create directory: \(parentDir)")
            } else {
                try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                if verbose {
                    print("Created directory: \(parentDir)")
                }
            }
        }

        if dryRun {
            print("Would create worktree at \(path) with branch \(branch)")
            return false
        }

        // For PRs, the branch already exists remotely - fetch and use it
        if hasPRBranch {
            // Fetch the branch from remote
            if verbose {
                print("Fetching branch \(branch) from remote...")
            }
            try await gitService.fetchBranch(branch)

            // Create worktree from existing branch (with recovery for branch conflicts)
            try await createWorktreeWithRecovery(
                gitService: gitService,
                at: path,
                branch: branch,
                isPR: true
            )
            return false
        }

        // For non-PR sources, try to create a new branch
        let branchExists = try await gitService.branchExists(branch)
        if branchExists {
            // Branch exists - create worktree from existing branch (with recovery)
            try await createWorktreeWithRecovery(
                gitService: gitService,
                at: path,
                branch: branch,
                isPR: false
            )
        } else {
            // Create new branch with worktree
            do {
                try await gitService.createWorktree(at: path, branch: branch)
                if verbose {
                    print("Created worktree with new branch: \(branch)")
                }
            } catch {
                throw GitError.worktreeCreationFailed("Failed to create worktree: \(error)")
            }
        }

        return false
    }

    /// Create a worktree from an existing branch, with automatic recovery if the branch
    /// is already checked out in another worktree (stale or active).
    private func createWorktreeWithRecovery(
        gitService: GitService,
        at path: String,
        branch: String,
        isPR: Bool
    ) async throws {
        do {
            try await gitService.createWorktreeFromExisting(at: path, branch: branch)
            if verbose {
                print("Created worktree from existing branch: \(branch)")
            }
        } catch {
            let errorMessage = String(describing: error)
            guard errorMessage.contains("is already used by worktree") else {
                let context = isPR ? "PR branch" : "Branch"
                throw GitError.worktreeCreationFailed("\(context) '\(branch)' worktree creation failed: \(error)")
            }

            // Branch is locked by another worktree - attempt recovery
            let conflictingPath = parseConflictingWorktreePath(from: errorMessage)
            let conflictingExists = conflictingPath.map { FileManager.default.fileExists(atPath: $0) } ?? false

            if !conflictingExists {
                // The conflicting worktree no longer exists on disk - prune stale reference and retry
                if verbose {
                    let displayPath = conflictingPath ?? "unknown path"
                    print("Conflicting worktree at \(displayPath) no longer exists on disk, pruning...")
                }
                try await gitService.pruneWorktrees()

                // Re-fetch the branch now that it's no longer "checked out"
                if isPR {
                    try await gitService.fetchBranch(branch)
                }

                try await gitService.createWorktreeFromExisting(at: path, branch: branch)
                if verbose {
                    print("Created worktree from existing branch after pruning: \(branch)")
                }
            } else {
                // Branch is genuinely checked out in another active worktree - force create
                if verbose {
                    print("Branch '\(branch)' is checked out at \(conflictingPath!), force-creating worktree...")
                }
                try await gitService.createWorktreeFromExistingForce(at: path, branch: branch)
                if verbose {
                    print("Created worktree (forced) from existing branch: \(branch)")
                }
            }
        }
    }

    /// Parse the conflicting worktree path from a git "already used by worktree" error message.
    private func parseConflictingWorktreePath(from errorMessage: String) -> String? {
        if let match = errorMessage.firstMatch(of: /is already used by worktree at '([^']+)'/) {
            return String(match.1)
        }
        return nil
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
