import Foundation
import Testing
@testable import sprout

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
}
