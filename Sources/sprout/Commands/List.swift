import ArgumentParser
import Foundation

/// Lists all worktrees with their branches.
struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all worktrees"
    )

    @Flag(name: .long, help: "Output only branch names (for piping)")
    var branchesOnly: Bool = false

    @Flag(name: .long, help: "Include the main worktree")
    var includeMain: Bool = false

    func run() async throws {
        let gitService = GitService()
        let worktrees = try await gitService.listWorktrees(includeMain: includeMain)

        if worktrees.isEmpty {
            if !branchesOnly {
                print("No worktrees found.")
            }
            return
        }

        if branchesOnly {
            for wt in worktrees {
                print(wt.branch)
            }
        } else {
            for wt in worktrees {
                print("\(wt.branch)\t\(wt.path)")
            }
        }
    }
}
