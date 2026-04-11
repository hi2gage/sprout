import Foundation
import Testing
@testable import sprout

@Suite("Config loader")
struct ConfigLoaderServiceTests {
    @Test("loads TOML config", .tags(.service))
    func configLoaderLoadsFile() throws {
        try withTemporaryDirectory { dir in
            let configFile = dir.appendingPathComponent("config.toml")
            let toml = """
            [launch]
            script = "echo hi"
            """
            try toml.write(to: configFile, atomically: true, encoding: .utf8)

            let config = try ConfigLoader.load(from: configFile.path)
            #expect(config.launch.script == "echo hi")
            #expect(config.launch.resolvedPRScript == "echo hi")
        }
    }

    @Test("throws for missing file", .tags(.service))
    func configLoaderMissingFile() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.load(from: "/tmp/definitely-missing-sprout-config.toml")
        }
    }

    @Test("throws for invalid TOML", .tags(.service))
    func configLoaderInvalidTOML() throws {
        try withTemporaryDirectory { dir in
            let configFile = dir.appendingPathComponent("config.toml")
            let invalidTOML = """
            [launch
            script = "echo hi"
            """
            try invalidTOML.write(to: configFile, atomically: true, encoding: .utf8)

            #expect(throws: ConfigError.self) {
                try ConfigLoader.load(from: configFile.path)
            }
        }
    }

    @Test("decodes default_branch_type from worktree config", .tags(.service))
    func configLoaderDefaultBranchType() throws {
        try withTemporaryDirectory { dir in
            let configFile = dir.appendingPathComponent("config.toml")
            let toml = """
            [launch]
            script = "echo hi"

            [worktree]
            branch_template = "{branch_type}/{ticket_id}/{slug}"
            default_branch_type = "chore"
            """
            try toml.write(to: configFile, atomically: true, encoding: .utf8)

            let config = try ConfigLoader.load(from: configFile.path)
            #expect(config.worktree?.defaultBranchType == "chore")
            #expect(config.worktree?.resolvedDefaultBranchType == "chore")
        }
    }

    @Test("resolvedDefaultBranchType falls back to feature", .tags(.service))
    func configLoaderDefaultBranchTypeFallback() throws {
        try withTemporaryDirectory { dir in
            let configFile = dir.appendingPathComponent("config.toml")
            let toml = """
            [launch]
            script = "echo hi"

            [worktree]
            branch_template = "{branch_type}/{ticket_id}"
            """
            try toml.write(to: configFile, atomically: true, encoding: .utf8)

            let config = try ConfigLoader.load(from: configFile.path)
            #expect(config.worktree?.defaultBranchType == nil)
            #expect(config.worktree?.resolvedDefaultBranchType == "feature")
        }
    }

}
