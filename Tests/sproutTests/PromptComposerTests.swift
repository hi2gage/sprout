import Testing
@testable import sprout

@Suite("Prompt composer")
struct PromptComposerTests {
    @Test("includes prefix/body/suffix with interpolation", .tags(.unit))
    func promptComposer() {
        let config = PromptConfig(prefix: "User: {user}", template: "# {title}\n\n{description}", suffix: "Path: {worktree}")
        let composer = PromptComposer(config: config)
        let variables = [
            "user": "sam",
            "title": "Implement cache",
            "description": "Add LRU cache",
            "worktree": "/tmp/worktrees/cache"
        ]

        let output = composer.composeContent(
            context: TicketContext(ticketId: "IOS-1", title: "Implement cache", description: "Add LRU cache", slug: "implement-cache"),
            variables: variables
        )

        #expect(output.contains("User: sam"))
        #expect(output.contains("# Implement cache"))
        #expect(output.contains("Path: /tmp/worktrees/cache"))
    }
}
