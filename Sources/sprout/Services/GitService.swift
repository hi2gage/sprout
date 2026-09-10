import Foundation
#if canImport(ObjCExceptionCatcher)
import ObjCExceptionCatcher
#endif
// `kill`/`errno`/`getpid` come from the platform C library, which differs off Apple platforms.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Git operations using Foundation Process
struct GitService {
    let workingDirectoryURL: URL?

    init(workingDirectoryURL: URL? = nil) {
        self.workingDirectoryURL = workingDirectoryURL
    }

    /// Runs `body`, converting any Objective-C `NSException` it raises into a thrown
    /// `GitError.processException`.
    ///
    /// `Process` can raise uncatchable (from Swift) `NSException`s — e.g. when the inherited
    /// working directory was deleted mid-prune — which would otherwise abort the whole
    /// process before cleanup (branch deletion, the post-prune hook) can run.
    private func catchingProcessExceptions(_ body: () -> Void) throws {
#if canImport(ObjCExceptionCatcher)
        if let exception = oec_runCatchingExceptions(body) {
            throw GitError.processException(exception.name.rawValue, exception.reason)
        }
#else
        // No Objective-C runtime, so `Process` cannot raise an `NSException` for us to
        // intercept. Calling `body` directly is the complete behaviour here, not a stub.
        body()
#endif
    }

    /// Run a git command and return stdout
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = workingDirectoryURL

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
        var captured: (stdout: String, stderr: String, success: Bool)?
        var swiftError: Error?

        // The `Process` setup and launch can raise Objective-C `NSException`s that Swift's
        // `do`/`catch` cannot intercept; run them inside the exception guard so a failure
        // surfaces as a thrown error instead of aborting the process.
        try catchingProcessExceptions {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git"] + arguments
                process.currentDirectoryURL = workingDirectoryURL

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

                captured = (outStr, errStr, process.terminationStatus == 0)
            } catch {
                swiftError = error
            }
        }

        if let swiftError {
            throw swiftError
        }
        guard let captured else {
            throw GitError.commandFailed("git \(arguments.first ?? "")", "subprocess produced no result")
        }
        return captured
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

    /// Create a worktree from an existing branch, even if it's checked out in another worktree
    func createWorktreeFromExistingForce(at path: String, branch: String) async throws {
        let result = try runWithStderr(["worktree", "add", "--force", path, branch])
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

    /// How a worktree's `git worktree lock` should be treated by a removal.
    enum WorktreeLockState: Equatable {
        /// Not locked — safe to remove.
        case unlocked
        /// Locked, and the process named in the lock reason is still running.
        case heldByLiveProcess(pid: pid_t, reason: String)
        /// Locked by a process that has since exited — a leftover from a crashed session.
        case staleLock(pid: pid_t, reason: String)
        /// Locked with no pid in the reason, so ownership can't be verified. Treated as held,
        /// because it may be a deliberate manual `git worktree lock`.
        case lockedWithUncheckableOwner(reason: String)
    }

    /// A worktree as recorded by `git worktree list --porcelain`.
    struct WorktreeRegistration: Equatable {
        /// The main working tree, which must never be removed.
        let isMain: Bool
        let lock: WorktreeLockState
    }

    /// Look up `path` in `git worktree list --porcelain`.
    ///
    /// Returns nil only when git answered successfully and `path` is genuinely not a
    /// registered worktree. A *failed* `git worktree list` throws instead: callers use this to
    /// decide whether destroying `path` is safe, so "I could not find out" must never be
    /// reported as "nothing objects" (that read once let `removeWorktree` delete a whole main
    /// checkout whenever git errored — e.g. `safe.directory`/dubious ownership, or a corrupt
    /// `.git`).
    func worktreeRegistration(at path: String) throws -> WorktreeRegistration? {
        let result = try runWithStderr(["worktree", "list", "--porcelain"])
        guard result.success else {
            throw GitError.commandFailed("git worktree list", result.stderr)
        }

        let target = Self.canonicalPath(path)
        var blockIndex = -1
        var matchedIndex: Int?
        var rawReason: String?

        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("worktree ") {
                // A new block begins. If the previous one was our match, we're done — the
                // `locked` line (when present) always sits inside its own worktree's block.
                if matchedIndex != nil { break }
                blockIndex += 1
                if Self.canonicalPath(String(line.dropFirst("worktree ".count))) == target {
                    matchedIndex = blockIndex
                }
            } else if matchedIndex != nil, line == "locked" || line.hasPrefix("locked ") {
                rawReason = line == "locked" ? "" : String(line.dropFirst("locked ".count))
            }
        }

        guard let matchedIndex else { return nil }
        // git always emits the main working tree first.
        return WorktreeRegistration(isMain: matchedIndex == 0, lock: Self.lockState(from: rawReason))
    }

    /// Classify a `locked` reason string (nil = no `locked` line at all).
    private static func lockState(from rawReason: String?) -> WorktreeLockState {
        guard let rawReason else { return .unlocked }
        if let match = rawReason.firstMatch(of: /\bpid\s+(\d+)/), let pid = pid_t(match.1) {
            return processIsRunning(pid)
                ? .heldByLiveProcess(pid: pid, reason: rawReason)
                : .staleLock(pid: pid, reason: rawReason)
        }
        return .lockedWithUncheckableOwner(reason: rawReason)
    }

    /// Settle git's objections to removing `path`, throwing when removal must not proceed:
    /// the main working tree, a lock held by a live process, and a lock whose owner cannot be
    /// verified (which may be a deliberate manual `git worktree lock`). A stale lock, whose
    /// owning process has exited, is cleared instead, since otherwise a crashed session blocks
    /// every future prune of that worktree; the unlock must succeed, because `git worktree
    /// remove` refuses a locked worktree with a single `--force`, so continuing without it
    /// would delete the working files and leave the registration behind for good.
    ///
    /// Returns false when `path` is not a registered worktree, which the caller treats as a
    /// refusal rather than permission. Deliberately callable more than once per removal: the
    /// verdict goes stale the moment it is read, so it is re-settled before anything
    /// destructive runs.
    @discardableResult
    private func requireRemovable(at path: String) throws -> Bool {
        guard let registration = try worktreeRegistration(at: path) else { return false }
        guard !registration.isMain else {
            throw GitError.commandFailed(
                "git worktree remove",
                "refusing to remove the main working tree at \(path)"
            )
        }
        switch registration.lock {
        case .unlocked:
            break
        case .heldByLiveProcess(let pid, let reason):
            throw GitError.worktreeLocked(path, "held by running process \(pid) — \(reason)")
        case .lockedWithUncheckableOwner(let reason):
            throw GitError.worktreeLocked(path, reason)
        case .staleLock:
            let unlock = try runWithStderr(["worktree", "unlock", path])
            guard unlock.success else {
                throw GitError.worktreeLocked(path, "stale lock could not be cleared: \(unlock.stderr)")
            }
        }
        return true
    }

    /// Whether a pid currently maps to a running process.
    private static func processIsRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        // EPERM means the process exists but belongs to another user.
        return errno == EPERM
    }

    /// Resolve symlinks so paths from git and from callers compare equal (macOS hands out
    /// `/var/...` temp dirs that are really `/private/var/...`).
    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Remove a worktree, husk-proof against macOS `.DS_Store` regeneration races.
    ///
    /// A recursive delete unlinks a directory's children and then `rmdir`s the (now-empty)
    /// parent. On a Finder-/Spotlight-visible volume an open window makes macOS regenerate a
    /// `.DS_Store` in that window between those two steps, so the final `rmdir` fails with
    /// `ENOTEMPTY` and the directory survives as a near-empty husk — this defeats both
    /// `git worktree remove --force` and a plain `FileManager.removeItem`, no matter how many
    /// times they are retried, because the race can be lost on every pass.
    ///
    /// To sidestep the race entirely we relocate the whole worktree directory to a sibling
    /// path with a single atomic `rename(2)` (`FileManager.moveItem`), which does not walk the
    /// tree and so cannot be wedged by a regenerated child. That makes the registered `path`
    /// disappear at once; the relocated copy is then deleted best-effort (a `.DS_Store`
    /// regenerating inside it no longer matters, since `path` is already gone). `git worktree
    /// prune` reconciles git's metadata afterward. Throws only if `path` itself still exists.
    ///
    /// The relocate is a workaround for one specific *mechanical* failure — a regenerated
    /// `.DS_Store` wedging git's final `rmdir`. It must not be applied when git refuses the
    /// removal *on principle*, so those cases are rejected up front: relocating a worktree
    /// another process is actively using strands its lock and registration while the working
    /// files vanish (a torn half-prune), and relocating the main working tree would move the
    /// whole checkout aside and then delete it.
    func removeWorktree(at path: String) async throws {
        let fm = FileManager.default

        // Decide on git's own objections BEFORE touching anything on disk. An unregistered
        // path is a REFUSAL, not permission: the destructive fallback below would happily
        // `rename` and `rm -rf` any directory handed to it, so it may only ever run against a
        // path git confirms is one of its own non-main worktrees.
        guard try requireRemovable(at: path) else {
            guard fm.fileExists(atPath: path) else {
                // Nothing registered and nothing on disk, so removal is a no-op. `fileExists`
                // is also false for a path that is merely unreachable (worktree on an ejected
                // volume) or a dangling symlink, but git has to have never heard of the path
                // to get here at all: `git worktree remove --force` exits 0 and unregisters a
                // registered-but-absent worktree, so that case never reaches this branch.
                return
            }
            throw GitError.commandFailed(
                "git worktree remove",
                "refusing to remove '\(path)': not a registered worktree"
            )
        }

        // Prefer git's own removal for the clean, unraced case: it keeps git's metadata
        // consistent and, when nothing regenerates a `.DS_Store`, deletes the directory too.
        removeDSStoreFiles(under: path)
        let result = try runWithStderr(["worktree", "remove", path, "--force"])
        if result.success && !fm.fileExists(atPath: path) {
            return
        }
        let lastStderr = result.stderr

        // git either failed or left a husk. Atomically move the surviving directory aside so
        // the registered `path` is gone in one syscall — this dodges the child/parent race.
        if fm.fileExists(atPath: path) {
            // Settle git's objections AGAIN before the destructive part. The answer from
            // before the removal attempt is stale by now: `removeDSStoreFiles` alone can
            // spend seconds walking a large checkout, and `git worktree remove` failing is
            // exactly what a concurrent `git worktree lock` looks like from here. Relocating
            // a newly-locked worktree would produce the torn half-prune this method exists to
            // prevent, and permanently: `git worktree prune` skips locked entries, so the
            // registration would survive every later run pointing at nothing.
            _ = try requireRemovable(at: path)

            let parent = (path as NSString).deletingLastPathComponent
            let name = (path as NSString).lastPathComponent
            let trashPath = parent + "/.\(name).sprout-trash-\(UUID().uuidString)"
            try? fm.moveItem(atPath: path, toPath: trashPath)

            // Reclaim the disk: delete the relocated copy, retrying since the same race can
            // still defeat this recursive delete — but a leftover here is a hidden, unregistered
            // dotfile, not a worktree husk, and its workspace path no longer matches any
            // recorded `WorkspacePath`.
            for _ in 0..<3 where fm.fileExists(atPath: trashPath) {
                removeDSStoreFiles(under: trashPath)
                try? fm.removeItem(atPath: trashPath)
            }

            // Fallback if the relocate itself failed (e.g. a permissions issue): try in place.
            for _ in 0..<3 where fm.fileExists(atPath: path) {
                removeDSStoreFiles(under: path)
                try? fm.removeItem(atPath: path)
            }
        }

        // Reconcile git's metadata: if the worktree is still registered but its directory is
        // now gone, prune clears the dangling entry.
        _ = try? runWithStderr(["worktree", "prune"])

        // Success requires the registered path to be gone. A leftover dotted trash copy is
        // unregistered and invisible to `git worktree list` / plain `ls`, so it is not a husk.
        if fm.fileExists(atPath: path) {
            throw GitError.commandFailed("git worktree remove", lastStderr)
        }
    }

    /// Delete stray `.DS_Store` files under a path so git's final `rmdir` can succeed.
    private func removeDSStoreFiles(under path: String) {
        // Route through the exception guard: `Process` can raise an NSException here too, and
        // this is best-effort cleanup — swallow any failure rather than abort the prune.
        try? catchingProcessExceptions {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            process.arguments = [path, "-name", ".DS_Store", "-delete"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
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
