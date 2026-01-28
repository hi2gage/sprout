import Foundation

/// Git operations using Foundation Process
struct GitService {
    /// Run a git command and return stdout
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Run a git command, capturing stderr too
    private func runWithStderr(_ arguments: [String]) throws -> (stdout: String, stderr: String, success: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (outStr, errStr, process.terminationStatus == 0)
    }

    /// Get the root directory of the current git repository
    func getRepoRoot() async throws -> String {
        let result = try runWithStderr(["rev-parse", "--show-toplevel"])
        guard result.success, !result.stdout.isEmpty else {
            throw GitError.notInRepo
        }
        return result.stdout
    }

    /// Create a new worktree with a new branch
    func createWorktree(at path: String, branch: String) async throws {
        let result = try runWithStderr(["worktree", "add", path, "-b", branch])
        guard result.success else {
            throw GitError.worktreeCreationFailed(result.stderr)
        }
    }

    /// Create a worktree from an existing branch
    func createWorktreeFromExisting(at path: String, branch: String) async throws {
        let result = try runWithStderr(["worktree", "add", path, branch])
        guard result.success else {
            throw GitError.worktreeCreationFailed(result.stderr)
        }
    }

    /// Get the current repo's owner/repo from the remote origin
    /// Returns format like "owner/repo" (e.g., "hi2gage/FreshWall")
    func getRemoteRepo() async throws -> String? {
        let result = try runWithStderr(["remote", "get-url", "origin"])
        guard result.success else { return nil }
        return extractRepoFromRemoteURL(result.stdout)
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

    /// List all worktrees (excluding the main one by default).
    func listWorktrees(includeMain: Bool = false) async throws -> [(path: String, branch: String)] {
        let result = try runWithStderr(["worktree", "list", "--porcelain"])
        guard result.success else { return [] }

        var worktrees: [(path: String, branch: String)] = []
        var currentPath: String?
        var currentBranch: String?

        for line in result.stdout.split(separator: "\n") {
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

        // Filter out main worktree unless requested
        if includeMain {
            return worktrees
        }
        return worktrees.filter { $0.path.contains("worktrees") }
    }

    /// Find an existing worktree by branch name (returns the path if found)
    func findWorktreeByBranch(_ branch: String) async throws -> String? {
        let worktrees = try await listWorktrees()
        return worktrees.first { $0.branch == branch }?.path
    }

    /// Remove a worktree
    func removeWorktree(at path: String) async throws {
        let result = try runWithStderr(["worktree", "remove", path, "--force"])
        guard result.success else {
            throw GitError.commandFailed("git worktree remove", result.stderr)
        }
    }

    /// Delete a local branch
    func deleteBranch(_ branch: String) async throws {
        let result = try runWithStderr(["branch", "-D", branch])
        guard result.success else {
            throw GitError.commandFailed("git branch -D", result.stderr)
        }
    }

    /// Prune stale worktree references
    func pruneWorktrees() async throws {
        _ = try runWithStderr(["worktree", "prune"])
    }

    /// Fetch a specific branch from the remote
    func fetchBranch(_ branch: String) async throws {
        let result = try runWithStderr(["fetch", "origin", "\(branch):\(branch)"])
        // Ignore errors - the branch might already be up to date or local
        if !result.success {
            // Try a simple fetch if the refspec fails
            _ = try? runWithStderr(["fetch", "origin", branch])
        }
    }

    /// Check if a branch exists locally or remotely
    func branchExists(_ branch: String) async throws -> Bool {
        // Check local
        let localResult = try runWithStderr(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"])
        if localResult.success {
            return true
        }

        // Check remote
        let remoteResult = try runWithStderr(["ls-remote", "--heads", "origin", branch])
        return !remoteResult.stdout.isEmpty
    }
}
