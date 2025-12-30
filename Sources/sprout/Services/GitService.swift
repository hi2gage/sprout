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

