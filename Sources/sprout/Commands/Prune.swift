import ArgumentParser
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import FuzzyTUI

/// Represents a worktree for display in the fuzzy finder
struct WorktreeItem: CustomStringConvertible, Hashable, Sendable, Equatable {
    let path: String
    let branch: String

    var description: String {
        "\(branch)  \u{001B}[90m\(path)\u{001B}[0m"
    }
}

struct Prune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clean up worktrees and branches"
    )

    @Flag(name: [.short, .long], help: "Delete without confirmation")
    var force: Bool = false

    @Flag(name: [.short, .long], help: "Show what would be deleted without deleting")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Read branch names from stdin (one per line)")
    var stdin: Bool = false

    @Argument(help: "Branch name or pattern to prune (optional - launches picker if not provided)")
    var branch: String?

    @Flag(name: [.short, .long], help: "Print verbose output")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        let gitService = GitService()
        let hooksService = HooksService()

        // Get list of worktrees
        let worktrees = try await gitService.listWorktrees()

        // Find the main repo root for hooks
        let mainRepoRoot: String?
        if let firstWorktree = worktrees.first {
            mainRepoRoot = hooksService.findMainRepoRoot(from: firstWorktree.path)
        } else {
            mainRepoRoot = try? await gitService.getRepoRoot()
        }

        if worktrees.isEmpty {
            print("No worktrees found.")
            return
        }

        // Filter if branch pattern provided
        let toRemove: [(path: String, branch: String)]

        if stdin {
            // Read branch names from stdin
            var branches: [String] = []
            while let line = readLine() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    branches.append(trimmed)
                }
            }

            if branches.isEmpty {
                print("No branches provided via stdin.")
                return
            }

            toRemove = worktrees.filter { branches.contains($0.branch) }
            if toRemove.isEmpty {
                print("No matching worktrees found for provided branches.")
                return
            }
        } else if let branch = branch {
            toRemove = worktrees.filter { $0.branch.contains(branch) }
            if toRemove.isEmpty {
                print("No worktrees matching '\(branch)' found.")
                print("\nAvailable worktrees:")
                for wt in worktrees {
                    print("  \(wt.branch) -> \(wt.path)")
                }
                return
            }
        } else if dryRun {
            // With --dry-run and no branch, show all worktrees
            toRemove = worktrees
        } else {
            // Use fuzzy finder for interactive selection
            let items = worktrees.map { WorktreeItem(path: $0.path, branch: $0.branch) }

            let stream = AsyncStream { continuation in
                for item in items {
                    continuation.yield(item)
                }
                continuation.finish()
            }

            let selector = try FuzzySelector(
                choices: stream,
                multipleSelection: true
            )

            let selected: [WorktreeItem]
            do {
                selected = try await selector.run()
            } catch {
                // User cancelled with Ctrl-C
                print("\nCancelled.")
                return
            }

            if selected.isEmpty {
                print("No worktrees selected.")
                return
            }

            toRemove = selected.map { (path: $0.path, branch: $0.branch) }

            // Skip confirmation - user already explicitly selected in fuzzy finder
            print("\nRemoving selected worktrees...")
        }

        // Confirm if not forced (only for non-interactive mode)
        if branch != nil && !force && !dryRun {
            print("\nWill remove:")
            for wt in toRemove {
                print("  - \(wt.branch)")
            }
            print("\nConfirm? [y/N]: ", terminator: "")
            fflush(stdout)
            guard let confirm = readLine()?.lowercased(), confirm == "y" || confirm == "yes" else {
                print("Cancelled.")
                return
            }
        }

        // Remove worktrees and branches
        for wt in toRemove {
            if dryRun {
                print("Would remove: \(wt.branch) (\(wt.path))")
                if let repoRoot = mainRepoRoot {
                    let hookPath = "\(repoRoot)/.sprout/hooks/post-prune"
                    if FileManager.default.fileExists(atPath: hookPath) {
                        print("  Would run post-prune hook")
                    }
                }
            } else {
                print("Removing \(wt.branch)...", terminator: " ")
                fflush(stdout)
                do {
                    // Capture worktree path before removal for hook
                    let worktreePath = wt.path

                    try await gitService.removeWorktree(at: wt.path)
                    try await gitService.deleteBranch(wt.branch)
                    print("done")

                    // Run post-prune hook if it exists
                    if let repoRoot = mainRepoRoot {
                        let env = HooksService.HookEnvironment(
                            worktreePath: worktreePath,
                            branch: wt.branch,
                            repoRoot: repoRoot
                        )
                        do {
                            let hookRan = try await hooksService.run(
                                .postPrune,
                                in: repoRoot,
                                environment: env,
                                verbose: verbose
                            )
                            if hookRan && verbose {
                                print("  post-prune hook completed")
                            }
                        } catch {
                            print("  post-prune hook failed: \(error)")
                        }
                    }
                } catch {
                    print("error: \(error)")
                }
            }
        }

        if !dryRun {
            // Clean up any stale worktree references
            try await gitService.pruneWorktrees()
            print("\nDone!")
        }
    }
}
