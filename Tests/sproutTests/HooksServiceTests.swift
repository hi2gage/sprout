import Foundation
import Testing
@testable import sprout

@Suite("Hooks service")
struct HooksServiceTests {
    @Test("resolves main repo root from worktree .git file", .tags(.service))
    func hooksServiceFindMainRepoRoot() throws {
        try withTemporaryDirectory { dir in
            let worktree = dir.appendingPathComponent("worktree")
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)

            let gitFile = worktree.appendingPathComponent(".git")
            let content = "gitdir: \(dir.path)/.git/worktrees/feature-123\n"
            try content.write(to: gitFile, atomically: true, encoding: .utf8)

            let hooks = HooksService()
            #expect(hooks.findMainRepoRoot(from: worktree.path) == dir.path)
        }
    }

    @Test("returns false for non-executable hook", .tags(.service))
    func hooksServiceNonExecutableHook() async throws {
        try await withTemporaryDirectory { dir in
            let hooksDir = dir.appendingPathComponent(".sprout/hooks")
            try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)

            let hookPath = hooksDir.appendingPathComponent("post-prune")
            let script = """
            #!/bin/sh
            echo should-not-run
            """
            try script.write(to: hookPath, atomically: true, encoding: .utf8)

            let hooks = HooksService()
            let didRun = try await hooks.run(
                .postPrune,
                in: dir.path,
                environment: .init(repoRoot: dir.path),
                verbose: false
            )
            #expect(didRun == false)
        }
    }

    @Test("throws when hook exits non-zero", .tags(.service))
    func hooksServiceHookFailure() async throws {
        try await withTemporaryDirectory { dir in
            let hooksDir = dir.appendingPathComponent(".sprout/hooks")
            try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)

            let hookPath = hooksDir.appendingPathComponent("post-prune")
            let script = """
            #!/bin/sh
            exit 9
            """
            try script.write(to: hookPath, atomically: true, encoding: .utf8)
            _ = try runProcess(["chmod", "+x", hookPath.path])

            let hooks = HooksService()
            await #expect(throws: HookError.self) {
                try await hooks.run(
                    .postPrune,
                    in: dir.path,
                    environment: .init(repoRoot: dir.path),
                    verbose: false
                )
            }
        }
    }

}
