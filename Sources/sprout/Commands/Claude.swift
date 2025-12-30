import ArgumentParser
import Foundation

struct Claude: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude",
        abstract: "Run Claude Code with a file and prompt."
    )

    @Argument(help: "File path to work on")
    var file: String

    @Argument(help: "Prompt describing what to do")
    var prompt: String

    @Flag(name: .shortAndLong, help: "Open in a new iTerm tab instead of current terminal")
    var newTab: Bool = false

    func run() throws {
        let fileManager = FileManager.default
        
        // Resolve to absolute path
        let absolutePath: String
        if file.hasPrefix("/") {
            absolutePath = file
        } else if file.hasPrefix("~") {
            absolutePath = NSString(string: file).expandingTildeInPath
        } else {
            absolutePath = fileManager.currentDirectoryPath + "/" + file
        }
        
        // Verify file exists
        guard fileManager.fileExists(atPath: absolutePath) else {
            throw ClaudeError.fileNotFound(file)
        }
        
        // Build the Claude command
        let fullPrompt = "Edit \(absolutePath): \(prompt)"
        let escapedPrompt = fullPrompt.replacingOccurrences(of: "\"", with: "\\\"")
        
        if newTab {
            // Open in new iTerm tab
            let script = """
            tell application "iTerm"
                activate
                tell current window
                    set newTab to (create tab with default profile)
                    tell current session of newTab
                        write text "claude \\"\(escapedPrompt)\\""
                    end tell
                end tell
            end tell
            """
            try shell("osascript -e '\(script)'")
        } else {
            // Run in current terminal
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "claude \"\(escapedPrompt)\""]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            
            try process.run()
            process.waitUntilExit()
        }
    }
    
    private func shell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw ClaudeError.commandFailed(command, process.terminationStatus)
        }
    }
}

enum ClaudeError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case commandFailed(String, Int32)
    
    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .commandFailed(let cmd, let code):
            return "Command failed (\(code)): \(cmd)"
        }
    }
}
