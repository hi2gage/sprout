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
}
