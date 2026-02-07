import Testing
@testable import sprout

@Suite("Script runner")
struct ScriptRunnerTests {
    @Test("executes success and fails on non-zero exit", .tags(.service))
    func scriptRunnerBehavior() async throws {
        let runner = ScriptRunner()
        try await runner.execute("echo ok", verbose: false)

        await #expect(throws: ScriptError.self) {
            try await runner.execute("exit 7", verbose: false)
        }
    }
}
