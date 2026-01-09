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
        if let pr = githubPR {
            return .githubPR(pr, repo: nil)
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

        // Compute worktree path
        let pathTemplate = config.worktree?.resolvedPathTemplate ?? "../worktrees/{branch}"
        let worktreePath = interpolate(pathTemplate, with: [
            "branch": branchName,
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

    private func composePrompt(context: TicketContext, config: SproutConfig, variables: [String: String]) throws -> String {
        let composer = PromptComposer(config: config.prompt)
        return try composer.compose(context: context, variables: variables)
    }

    // MARK: - Worktree Management

    /// Ensure a worktree exists at the given path, creating it if needed.
    /// Returns true if worktree already existed, false if it was created.
    private func ensureWorktreeExists(at path: String, branch: String, hasPRBranch: Bool, dryRun: Bool) async throws -> Bool {
        let gitService = GitService()

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

            // Create worktree from existing branch
            do {
                try await gitService.createWorktreeFromExisting(at: path, branch: branch)
                if verbose {
                    print("Created worktree from existing branch: \(branch)")
                }
                return false
            } catch {
                throw GitError.worktreeCreationFailed("Failed to create worktree from PR branch '\(branch)': \(error)")
            }
        }

        // For non-PR sources, try to create a new branch
        let branchExists = try await gitService.branchExists(branch)
        if branchExists {
            // Branch exists - create worktree from existing branch
            do {
                try await gitService.createWorktreeFromExisting(at: path, branch: branch)
                if verbose {
                    print("Created worktree from existing branch: \(branch)")
                }
            } catch {
                throw GitError.worktreeCreationFailed("Branch '\(branch)' exists but worktree creation failed: \(error)")
            }
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
