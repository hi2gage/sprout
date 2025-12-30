import ArgumentParser

@main
struct Sprout: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sprout",
        abstract: "A personal CLI toolkit for development workflows.",
        version: "0.1.0",
        subcommands: [
            Claude.self,
            Worktree.self,
        ],
        defaultSubcommand: nil
    )
}
