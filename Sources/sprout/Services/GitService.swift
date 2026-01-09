import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Git operations using swift-subprocess
struct GitService {
    /// Get the root directory of the current git repository
    func getRepoRoot() async throws -> String {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["rev-parse", "--show-toplevel"],
            output: .string(limit: 4096),
            error: .discarded
        )

        guard result.terminationStatus.isSuccess else {
            throw GitError.notInRepo
        }

        guard let output = result.standardOutput else {
            throw GitError.notInRepo
        }

        return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /// Create a new worktree with a new branch
    func createWorktree(at path: String, branch: String) async throws {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["worktree", "add", path, "-b", branch],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard result.terminationStatus.isSuccess else {
            let stderr = result.standardError ?? "Unknown error"
            throw GitError.worktreeCreationFailed(stderr)
        }
    }

    /// Create a worktree from an existing branch
    func createWorktreeFromExisting(at path: String, branch: String) async throws {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["worktree", "add", path, branch],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard result.terminationStatus.isSuccess else {
            let stderr = result.standardError ?? "Unknown error"
            throw GitError.worktreeCreationFailed(stderr)
        }
    }

    /// Get the current repo's owner/repo from the remote origin
    /// Returns format like "owner/repo" (e.g., "hi2gage/FreshWall")
    func getRemoteRepo() async throws -> String? {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["remote", "get-url", "origin"],
            output: .string(limit: 4096),
            error: .discarded
        )

        guard result.terminationStatus.isSuccess,
              let output = result.standardOutput else {
            return nil
        }

        let url = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return extractRepoFromRemoteURL(url)
    }

    /// Extract owner/repo from various git remote URL formats
    private func extractRepoFromRemoteURL(_ url: String) -> String? {
        // SSH format: git@github.com:owner/repo.git
        if let match = url.firstMatch(of: /github\.com:([^\/]+\/[^\/]+?)(\.git)?$/) {
            return String(match.1)
        }
        // HTTPS format: https://github.com/owner/repo.git
        if let match = url.firstMatch(of: /github\.com\/([^\/]+\/[^\/]+?)(\.git)?$/) {
            return String(match.1)
        }
        return nil
    }

    /// List all worktrees (excluding the main one)
    func listWorktrees() async throws -> [(path: String, branch: String)] {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["worktree", "list", "--porcelain"],
            output: .string(limit: 65536),
            error: .discarded
        )

        guard result.terminationStatus.isSuccess,
              let output = result.standardOutput else {
            return []
        }

        var worktrees: [(path: String, branch: String)] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.hasPrefix("worktree ") {
                // Save previous worktree if complete
                if let path = currentPath, let branch = currentBranch {
                    worktrees.append((path: path, branch: branch))
                }
                currentPath = String(lineStr.dropFirst("worktree ".count))
                currentBranch = nil
            } else if lineStr.hasPrefix("branch refs/heads/") {
                currentBranch = String(lineStr.dropFirst("branch refs/heads/".count))
            }
        }

        // Add last worktree
        if let path = currentPath, let branch = currentBranch {
            worktrees.append((path: path, branch: branch))
        }

        // Filter out main worktree (it won't have a branch in the same format typically)
        // and only return worktrees that are in a "worktrees" directory
        return worktrees.filter { $0.path.contains("worktrees") }
    }

    /// Remove a worktree
    func removeWorktree(at path: String) async throws {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["worktree", "remove", path, "--force"],
            input: .none,
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard result.terminationStatus.isSuccess else {
            let stderr = result.standardError ?? "Unknown error"
            throw GitError.commandFailed("git worktree remove", stderr)
        }
    }

    /// Delete a local branch
    func deleteBranch(_ branch: String) async throws {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["branch", "-D", branch],
            input: .none,
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard result.terminationStatus.isSuccess else {
            let stderr = result.standardError ?? "Unknown error"
            throw GitError.commandFailed("git branch -D", stderr)
        }
    }

    /// Prune stale worktree references
    func pruneWorktrees() async throws {
        _ = try await Subprocess.run(
            .name("git"),
            arguments: ["worktree", "prune"],
            input: .none,
            output: .discarded,
            error: .discarded
        )
    }

    /// Fetch a specific branch from the remote
    func fetchBranch(_ branch: String) async throws {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: ["fetch", "origin", "\(branch):\(branch)"],
            input: .none,
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        // Ignore errors - the branch might already be up to date or local
        if !result.terminationStatus.isSuccess {
            // Try a simple fetch if the refspec fails
            _ = try await Subprocess.run(
                .name("git"),
                arguments: ["fetch", "origin", branch],
                input: .none,
                output: .discarded,
                error: .discarded
            )
        }
    }

    /// Check if a branch exists locally or remotely
    func branchExists(_ branch: String) async throws -> Bool {
        // Check local
        let localResult = try await Subprocess.run(
            .name("git"),
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            output: .discarded,
            error: .discarded
        )
        if localResult.terminationStatus.isSuccess {
            return true
        }

        // Check remote
        let remoteResult = try await Subprocess.run(
            .name("git"),
            arguments: ["ls-remote", "--heads", "origin", branch],
            output: .string(limit: 4096),
            error: .discarded
        )
        guard let output = remoteResult.standardOutput else {
            return false
        }
        return !output.isEmpty
    }
}

