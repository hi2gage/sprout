import Foundation

/// Executes repository-specific hooks from .sprout/hooks/
struct HooksService {
    /// Available hook types
    enum Hook: String {
        case postPrune = "post-prune"
        case prePrune = "pre-prune"
        case postLaunch = "post-launch"
    }

    /// Environment variables passed to hook scripts
    struct HookEnvironment {
        var worktreePath: String?
        var branch: String?
        var repoRoot: String?

        var asDict: [String: String] {
            var env: [String: String] = [:]
            if let path = worktreePath {
                env["SPROUT_WORKTREE_PATH"] = path
            }
            if let branch = branch {
                env["SPROUT_BRANCH"] = branch
            }
            if let root = repoRoot {
                env["SPROUT_REPO_ROOT"] = root
            }
            return env
        }
    }

    /// Run a hook if it exists in the repository
    /// - Parameters:
    ///   - hook: The hook type to run
    ///   - repoRoot: Root directory of the repository
    ///   - environment: Environment variables to pass to the script
    ///   - verbose: Whether to print debug output
    /// - Returns: true if hook was found and executed, false if no hook exists
    @discardableResult
    func run(
        _ hook: Hook,
        in repoRoot: String,
        environment: HookEnvironment,
        verbose: Bool = false
    ) async throws -> Bool {
        let hookPath = "\(repoRoot)/.sprout/hooks/\(hook.rawValue)"
        let expandedPath = NSString(string: hookPath).expandingTildeInPath

        // Check if hook exists
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            if verbose {
                print("No \(hook.rawValue) hook found at \(hookPath)")
            }
            return false
        }

        // Check if executable
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            print("Warning: Hook exists but is not executable: \(hookPath)")
            print("Run: chmod +x \(hookPath)")
            return false
        }

        if verbose {
            print("Running \(hook.rawValue) hook...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: expandedPath)
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)

        // Merge with existing environment
        var processEnv = ProcessInfo.processInfo.environment
        for (key, value) in environment.asDict {
            processEnv[key] = value
        }
        process.environment = processEnv

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        // Print output
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        if let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outStr.isEmpty {
            print(outStr)
        }

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        if let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !errStr.isEmpty {
            FileHandle.standardError.write(Data(errStr.utf8))
            FileHandle.standardError.write(Data("\n".utf8))
        }

        if process.terminationStatus != 0 {
            throw HookError.executionFailed(hook.rawValue, Int(process.terminationStatus))
        }

        return true
    }

    /// Find the main repo root from a worktree path
    /// Worktrees are typically at ../worktrees/{branch}, so main repo is a sibling
    func findMainRepoRoot(from worktreePath: String) -> String? {
        // Check if this worktree has a .git file (not directory) pointing to main repo
        let gitPath = "\(worktreePath)/.git"

        guard FileManager.default.fileExists(atPath: gitPath) else {
            return nil
        }

        // For worktrees, .git is a file containing "gitdir: /path/to/main/.git/worktrees/branch"
        guard let contents = try? String(contentsOfFile: gitPath, encoding: .utf8),
              contents.hasPrefix("gitdir:") else {
            // This is the main repo (has .git directory)
            return worktreePath
        }

        // Parse the gitdir path to find main repo
        // Format: gitdir: /path/to/main/.git/worktrees/branchname
        let gitdirPath = contents
            .replacingOccurrences(of: "gitdir:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Go up from .git/worktrees/branch to get main repo root
        if let range = gitdirPath.range(of: "/.git/worktrees/") {
            return String(gitdirPath[..<range.lowerBound])
        }

        return nil
    }
}

/// Errors from hook execution
enum HookError: Error, CustomStringConvertible {
    case executionFailed(String, Int)

    var description: String {
        switch self {
        case .executionFailed(let hook, let code):
            return "Hook '\(hook)' failed with exit code \(code)"
        }
    }
}
