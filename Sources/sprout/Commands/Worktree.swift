import ArgumentParser
import Foundation

struct Worktree: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: "Manage git worktrees and spawn Claude Code instances.",
        subcommands: [
            Create.self,
            List.self,
            Open.self,
            Remove.self,
            Cleanup.self,
        ]
    )
}

// MARK: - Create

extension Worktree {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new worktree and optionally start Claude Code."
        )

        @Argument(help: "Branch name for the worktree (e.g., feature/new-dashboard)")
        var branch: String

        @Option(name: .shortAndLong, help: "Prompt to pass to Claude Code")
        var prompt: String?

        @Flag(name: .shortAndLong, help: "Open in Cursor instead of iTerm")
        var cursor: Bool = false

        func run() throws {
            let git = GitWorktree()
            try git.create(branch: branch, prompt: prompt, openInCursor: cursor)
        }
    }
}

// MARK: - List

extension Worktree {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all active worktrees with their status."
        )

        @Flag(name: .shortAndLong, help: "Show detailed status including git info")
        var verbose: Bool = false

        func run() throws {
            let git = GitWorktree()
            try git.list(verbose: verbose)
        }
    }
}

// MARK: - Open

extension Worktree {
    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open an existing worktree."
        )

        @Argument(help: "Branch name of the worktree to open")
        var branch: String

        @Flag(name: .shortAndLong, help: "Open in Cursor")
        var cursor: Bool = false

        @Flag(name: .shortAndLong, help: "Open in Xcode")
        var xcode: Bool = false

        func run() throws {
            let git = GitWorktree()
            try git.open(branch: branch, inCursor: cursor, inXcode: xcode)
        }
    }
}

// MARK: - Remove

extension Worktree {
    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a worktree."
        )

        @Argument(help: "Branch name of the worktree to remove")
        var branch: String

        @Flag(name: .shortAndLong, help: "Force removal even with uncommitted changes")
        var force: Bool = false

        func run() throws {
            let git = GitWorktree()
            try git.remove(branch: branch, force: force)
        }
    }
}

// MARK: - Cleanup

extension Worktree {
    struct Cleanup: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove all worktrees."
        )

        @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
        var yes: Bool = false

        func run() throws {
            let git = GitWorktree()
            try git.cleanup(skipConfirmation: yes)
        }
    }
}
