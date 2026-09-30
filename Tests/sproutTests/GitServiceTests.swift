import Foundation
import Testing
@testable import sprout
// `getpid()` comes from the platform C library.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("Git service")
struct GitServiceTests {
    @Test("gets repo root and detects local branch", .tags(.service))
    func gitServiceRepoAndBranch() async throws {
        try await withTemporaryDirectory { dir in
            _ = try runProcess(["git", "init"], cwd: dir)
            _ = try runProcess(["git", "config", "user.email", "tests@example.com"], cwd: dir)
            _ = try runProcess(["git", "config", "user.name", "sprout-tests"], cwd: dir)
            try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try runProcess(["git", "add", "."], cwd: dir)
            _ = try runProcess(["git", "commit", "-m", "init"], cwd: dir)
            _ = try runProcess(["git", "checkout", "-b", "feature/test-branch"], cwd: dir)

            let service = GitService(workingDirectoryURL: dir)
            let root = try await service.getRepoRoot()
            let normalizedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            let normalizedDir = dir.resolvingSymlinksInPath().path
            #expect(normalizedRoot == normalizedDir)
            #expect(try await service.branchExists("feature/test-branch"))
            #expect(!(try await service.branchExists("missing/branch")))
        }
    }

    @Test("parses GitHub remote URL formats", .tags(.service))
    func gitServiceRemoteParsing() async throws {
        try await withTemporaryDirectory { dir in
            _ = try runProcess(["git", "init"], cwd: dir)

            let service = GitService(workingDirectoryURL: dir)

            _ = try runProcess(["git", "remote", "add", "origin", "https://github.com/apple/swift.git"], cwd: dir)
            #expect(try await service.getRemoteRepo() == "apple/swift")

            _ = try runProcess(["git", "remote", "set-url", "origin", "git@github.com:pointfreeco/swift-dependencies.git"], cwd: dir)
            #expect(try await service.getRemoteRepo() == "pointfreeco/swift-dependencies")
        }
    }

    @Test("deleteBranch throws for missing branch", .tags(.service))
    func gitServiceDeleteMissingBranch() async throws {
        try await withTemporaryDirectory { dir in
            _ = try runProcess(["git", "init"], cwd: dir)
            _ = try runProcess(["git", "config", "user.email", "tests@example.com"], cwd: dir)
            _ = try runProcess(["git", "config", "user.name", "sprout-tests"], cwd: dir)
            try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try runProcess(["git", "add", "."], cwd: dir)
            _ = try runProcess(["git", "commit", "-m", "init"], cwd: dir)

            let service = GitService(workingDirectoryURL: dir)
            await #expect(throws: GitError.self) {
                try await service.deleteBranch("missing/branch")
            }
        }
    }

    @Test("removeWorktree unregisters and deletes the directory", .tags(.service))
    func gitServiceRemoveWorktree() async throws {
        try await withTemporaryDirectory { dir in
            _ = try runProcess(["git", "init"], cwd: dir)
            _ = try runProcess(["git", "config", "user.email", "tests@example.com"], cwd: dir)
            _ = try runProcess(["git", "config", "user.name", "sprout-tests"], cwd: dir)
            try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try runProcess(["git", "add", "."], cwd: dir)
            _ = try runProcess(["git", "commit", "-m", "init"], cwd: dir)

            let wt = dir.appendingPathComponent("worktrees/pr-test", isDirectory: true)
            _ = try runProcess(["git", "worktree", "add", wt.path, "-b", "feature/test/demo"], cwd: dir)
            #expect(FileManager.default.fileExists(atPath: wt.path))

            let service = GitService(workingDirectoryURL: dir)
            try await service.removeWorktree(at: wt.path)

            #expect(!FileManager.default.fileExists(atPath: wt.path))
            let (_, listOut, _) = try runProcess(["git", "worktree", "list"], cwd: dir)
            #expect(!listOut.contains("pr-test"))
        }
    }

    @Test("removeWorktree leaves no husk under a .DS_Store regeneration race", .tags(.service))
    func gitServiceRemoveWorktreeNoHusk() async throws {
        try await withTemporaryDirectory { dir in
            _ = try runProcess(["git", "init"], cwd: dir)
            _ = try runProcess(["git", "config", "user.email", "tests@example.com"], cwd: dir)
            _ = try runProcess(["git", "config", "user.name", "sprout-tests"], cwd: dir)
            try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try runProcess(["git", "add", "."], cwd: dir)
            _ = try runProcess(["git", "commit", "-m", "init"], cwd: dir)

            let wt = dir.appendingPathComponent("worktrees/pr-race", isDirectory: true)
            _ = try runProcess(["git", "worktree", "add", wt.path, "-b", "feature/test/race"], cwd: dir)
            let bundle = wt.appendingPathComponent("FetchHop/Fetch.xcworkspace", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

            // Simulate Finder/Spotlight continuously regenerating `.DS_Store` throughout the tree
            // while the worktree is being removed — the race that leaves a husk with a plain
            // recursive delete.
            let hammerDirs = [wt, wt.appendingPathComponent("FetchHop"), bundle]
            let hammer = Task.detached {
                while !Task.isCancelled {
                    for d in hammerDirs {
                        try? Data("x".utf8).write(to: d.appendingPathComponent(".DS_Store"))
                    }
                }
            }
            defer { hammer.cancel() }

            let service = GitService(workingDirectoryURL: dir)
            try await service.removeWorktree(at: wt.path)
            hammer.cancel()

            // The registered path must be gone (no husk) and unregistered from git.
            #expect(!FileManager.default.fileExists(atPath: wt.path))
            let (_, listOut, _) = try runProcess(["git", "worktree", "list"], cwd: dir)
            #expect(!listOut.contains("pr-race"))
        }
    }

    // MARK: - Removal preconditions (locks and the main working tree)

    @Test("removeWorktree refuses a worktree held by a live process", .tags(.service))
    func gitServiceRemoveWorktreeRefusesLiveLock() async throws {
        try await withTemporaryDirectory { dir in
            try initRepo(at: dir)

            let wt = dir.appendingPathComponent("worktrees/pr-locked", isDirectory: true)
            _ = try runProcess(["git", "worktree", "add", wt.path, "-b", "feature/test/locked"], cwd: dir)

            // Mirrors how an editor session tags its lock; this test process is certainly alive.
            let reason = "claude session pr-locked (pid \(getpid()) start now)"
            _ = try runProcess(["git", "worktree", "lock", "--reason", reason, wt.path], cwd: dir)

            let service = GitService(workingDirectoryURL: dir)
            let registration = try service.worktreeRegistration(at: wt.path)
            #expect(registration?.lock == .heldByLiveProcess(pid: getpid(), reason: reason))

            await #expect(throws: GitError.self) {
                try await service.removeWorktree(at: wt.path)
            }

            // The regression this guards: the working files AND the registration must survive.
            // Relocating the directory here would strand the lock and leave a torn half-prune.
            #expect(FileManager.default.fileExists(atPath: wt.path))
            let (_, listOut, _) = try runProcess(["git", "worktree", "list"], cwd: dir)
            #expect(listOut.contains("pr-locked"))
        }
    }

    @Test("removeWorktree clears a stale lock and removes the worktree", .tags(.service))
    func gitServiceRemoveWorktreeClearsStaleLock() async throws {
        try await withTemporaryDirectory { dir in
            try initRepo(at: dir)

            let wt = dir.appendingPathComponent("worktrees/pr-stale", isDirectory: true)
            _ = try runProcess(["git", "worktree", "add", wt.path, "-b", "feature/test/stale"], cwd: dir)

            // A crashed session's leftover lock: the pid is real but no longer running.
            let deadPID = try reapedPID()
            let reason = "claude session pr-stale (pid \(deadPID) start earlier)"
            _ = try runProcess(["git", "worktree", "lock", "--reason", reason, wt.path], cwd: dir)

            let service = GitService(workingDirectoryURL: dir)
            let registration = try service.worktreeRegistration(at: wt.path)
            #expect(registration?.lock == .staleLock(pid: deadPID, reason: reason))

            // A stale lock must not block the prune forever.
            try await service.removeWorktree(at: wt.path)

            #expect(!FileManager.default.fileExists(atPath: wt.path))
            let (_, listOut, _) = try runProcess(["git", "worktree", "list"], cwd: dir)
            #expect(!listOut.contains("pr-stale"))
        }
    }

    @Test("removeWorktree refuses a lock whose owner cannot be checked", .tags(.service))
    func gitServiceRemoveWorktreeRefusesUncheckableLock() async throws {
        try await withTemporaryDirectory { dir in
            try initRepo(at: dir)

            let wt = dir.appendingPathComponent("worktrees/pr-manual", isDirectory: true)
            _ = try runProcess(["git", "worktree", "add", wt.path, "-b", "feature/test/manual"], cwd: dir)

            // No pid in the reason — could be a deliberate manual lock, so stay conservative.
            _ = try runProcess(["git", "worktree", "lock", "--reason", "held by hand", wt.path], cwd: dir)

            let service = GitService(workingDirectoryURL: dir)
            let registration = try service.worktreeRegistration(at: wt.path)
            #expect(registration?.lock == .lockedWithUncheckableOwner(reason: "held by hand"))

            await #expect(throws: GitError.self) {
                try await service.removeWorktree(at: wt.path)
            }
            #expect(FileManager.default.fileExists(atPath: wt.path))
        }
    }

    @Test("removeWorktree refuses the main working tree", .tags(.service))
    func gitServiceRemoveWorktreeRefusesMainWorktree() async throws {
        try await withTemporaryDirectory { dir in
            try initRepo(at: dir)

            let service = GitService(workingDirectoryURL: dir)
            let registration = try service.worktreeRegistration(at: dir.path)
            #expect(registration?.isMain == true)

            await #expect(throws: GitError.self) {
                try await service.removeWorktree(at: dir.path)
            }

            // Without this guard the husk-proofing would move the whole checkout aside
            // and then delete it.
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("README.md").path))
        }
    }

    @Test("removeWorktree refuses a directory git does not register as a worktree", .tags(.service))
    func gitServiceRemoveWorktreeRefusesUnregisteredPath() async throws {
        try await withTemporaryDirectory { dir in
            try initRepo(at: dir)

            // A plain directory inside the repo — never `git worktree add`ed.
            let plain = dir.appendingPathComponent("not-a-worktree", isDirectory: true)
            try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
            try "keep me".write(to: plain.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)

            let service = GitService(workingDirectoryURL: dir)
            #expect(try service.worktreeRegistration(at: plain.path) == nil)

            await #expect(throws: GitError.self) {
                try await service.removeWorktree(at: plain.path)
            }

            // Without the refusal the husk-proofing would `rename` this aside and `rm -rf` it.
            #expect(FileManager.default.fileExists(atPath: plain.appendingPathComponent("data.txt").path))
        }
    }

    @Test("removeWorktree throws when git cannot report the worktree list", .tags(.service))
    func gitServiceRemoveWorktreeThrowsWhenGitFails() async throws {
        try await withTemporaryDirectory { dir in
            // Deliberately NOT a git repo, so `git worktree list` fails.
            let victim = dir.appendingPathComponent("checkout", isDirectory: true)
            try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
            try "precious".write(to: victim.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

            let service = GitService(workingDirectoryURL: dir)
            #expect(throws: GitError.self) {
                try service.worktreeRegistration(at: victim.path)
            }
            await #expect(throws: GitError.self) {
                try await service.removeWorktree(at: victim.path)
            }

            // "I could not find out" must never be treated as "nothing objects": when this
            // returned nil instead of throwing, removeWorktree deleted the whole directory
            // and reported success.
            #expect(FileManager.default.fileExists(atPath: victim.appendingPathComponent("README.md").path))
        }
    }

    @Test("removeWorktree is a no-op for a path that is neither registered nor present", .tags(.service))
    func gitServiceRemoveWorktreeMissingPathIsNoOp() async throws {
        try await withTemporaryDirectory { dir in
            try initRepo(at: dir)
            let service = GitService(workingDirectoryURL: dir)
            // Already gone: nothing to remove, and nothing to complain about.
            try await service.removeWorktree(at: dir.appendingPathComponent("gone").path)
        }
    }

    // MARK: - Helpers

    /// `git init` plus an identity and one commit, so worktrees can be added.
    private func initRepo(at dir: URL) throws {
        _ = try runProcess(["git", "init"], cwd: dir)
        _ = try runProcess(["git", "config", "user.email", "tests@example.com"], cwd: dir)
        _ = try runProcess(["git", "config", "user.name", "sprout-tests"], cwd: dir)
        try "hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try runProcess(["git", "add", "."], cwd: dir)
        _ = try runProcess(["git", "commit", "-m", "init"], cwd: dir)
    }

    /// A pid guaranteed not to be running: start a process, then wait for it to exit.
    private func reapedPID() throws -> pid_t {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        let pid = process.processIdentifier
        process.waitUntilExit()
        return pid
    }

}
