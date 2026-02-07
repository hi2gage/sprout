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

}
