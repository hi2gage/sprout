import Foundation

struct GitWorktree {
    private let fileManager = FileManager.default
    
    // MARK: - Create
    
    func create(branch: String, prompt: String?, openInCursor: Bool) throws {
        let repoRoot = try getRepoRoot()
        let worktreesDir = repoRoot.appendingPathComponent(".worktrees")
        let safeBranchName = branch.replacingOccurrences(of: "/", with: "-")
        let worktreePath = worktreesDir.appendingPathComponent(safeBranchName)
        
        // Create .worktrees directory if needed
        if !fileManager.fileExists(atPath: worktreesDir.path) {
            try fileManager.createDirectory(at: worktreesDir, withIntermediateDirectories: true)
            // Add to .gitignore if not already there
            try addToGitignore(repoRoot: repoRoot, entry: ".worktrees/")
        }
        
        // Check if branch exists remotely or locally
        let branchExists = try checkBranchExists(branch)
        
        if branchExists {
            // Worktree from existing branch
            try shell("git worktree add \"\(worktreePath.path)\" \(branch)")
        } else {
            // Create new branch from current HEAD
            try shell("git worktree add -b \(branch) \"\(worktreePath.path)\"")
        }
        
        print("✓ Created worktree at \(worktreePath.path)")
        
        // Open in terminal/editor
        if openInCursor {
            try openInCursorApp(path: worktreePath)
        } else {
            try openInITerm(path: worktreePath, prompt: prompt)
        }
    }
    
    // MARK: - List
    
    func list(verbose: Bool) throws {
        let output = try shellOutput("git worktree list --porcelain")
        let worktrees = parseWorktreeList(output)
        
        if worktrees.isEmpty {
            print("No worktrees found.")
            return
        }
        
        print("Active worktrees:\n")
        
        for wt in worktrees {
            let marker = wt.isBare ? " (bare)" : ""
            print("  \(wt.branch ?? "HEAD detached")\(marker)")
            print("    Path: \(wt.path)")
            
            if verbose {
                if let status = try? getWorktreeStatus(path: wt.path) {
                    print("    Status: \(status)")
                }
            }
            print("")
        }
    }
    
    // MARK: - Open
    
    func open(branch: String, inCursor: Bool, inXcode: Bool) throws {
        let worktreePath = try findWorktree(branch: branch)
        
        if inXcode {
            // Find .xcodeproj or .xcworkspace
            let contents = try fileManager.contentsOfDirectory(atPath: worktreePath.path)
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
                try shell("open \"\(worktreePath.appendingPathComponent(workspace).path)\"")
            } else if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                try shell("open \"\(worktreePath.appendingPathComponent(project).path)\"")
            } else {
                throw WorktreeError.noXcodeProject
            }
        } else if inCursor {
            try openInCursorApp(path: worktreePath)
        } else {
            try openInITerm(path: worktreePath, prompt: nil)
        }
    }
    
    // MARK: - Remove
    
    func remove(branch: String, force: Bool) throws {
        let worktreePath = try findWorktree(branch: branch)
        let forceFlag = force ? " --force" : ""
        try shell("git worktree remove\(forceFlag) \"\(worktreePath.path)\"")
        print("✓ Removed worktree: \(branch)")
    }
    
    // MARK: - Cleanup
    
    func cleanup(skipConfirmation: Bool) throws {
        let output = try shellOutput("git worktree list --porcelain")
        let worktrees = parseWorktreeList(output).filter { !$0.isBare }
        
        if worktrees.isEmpty {
            print("No worktrees to clean up.")
            return
        }
        
        if !skipConfirmation {
            print("This will remove \(worktrees.count) worktree(s):")
            for wt in worktrees {
                print("  - \(wt.branch ?? wt.path)")
            }
            print("\nContinue? [y/N] ", terminator: "")
            
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }
        
        for wt in worktrees {
            try shell("git worktree remove --force \"\(wt.path)\"")
            print("✓ Removed: \(wt.branch ?? wt.path)")
        }
        
        try shell("git worktree prune")
        print("\n✓ Cleanup complete")
    }
    
    // MARK: - Helpers
    
    private func getRepoRoot() throws -> URL {
        let path = try shellOutput("git rev-parse --show-toplevel").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path)
    }
    
    private func checkBranchExists(_ branch: String) throws -> Bool {
        // Check local
        let localResult = try? shellOutput("git show-ref --verify --quiet refs/heads/\(branch)")
        if localResult != nil { return true }
        
        // Check remote
        let remoteResult = try? shellOutput("git ls-remote --heads origin \(branch)")
        return remoteResult?.isEmpty == false
    }
    
    private func findWorktree(branch: String) throws -> URL {
        let repoRoot = try getRepoRoot()
        let safeBranchName = branch.replacingOccurrences(of: "/", with: "-")
        let worktreePath = repoRoot.appendingPathComponent(".worktrees").appendingPathComponent(safeBranchName)
        
        guard fileManager.fileExists(atPath: worktreePath.path) else {
            throw WorktreeError.notFound(branch)
        }
        
        return worktreePath
    }
    
    private func addToGitignore(repoRoot: URL, entry: String) throws {
        let gitignorePath = repoRoot.appendingPathComponent(".gitignore")
        
        if fileManager.fileExists(atPath: gitignorePath.path) {
            let contents = try String(contentsOf: gitignorePath, encoding: .utf8)
            if contents.contains(entry) { return }
            
            let newContents = contents + "\n\(entry)\n"
            try newContents.write(to: gitignorePath, atomically: true, encoding: .utf8)
        } else {
            try entry.write(to: gitignorePath, atomically: true, encoding: .utf8)
        }
    }
    
    private func openInITerm(path: URL, prompt: String?) throws {
        var script = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "cd \\"\(path.path)\\""
            end tell
        """
        
        if let prompt = prompt {
            let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
            script += """
            
                tell newWindow
                    set newTab to (create tab with default profile)
                    tell current session of newTab
                        write text "cd \\"\(path.path)\\" && claude \\"\(escapedPrompt)\\""
                    end tell
                end tell
            """
        }
        
        script += "\nend tell"
        
        try shell("osascript -e '\(script)'")
    }
    
    private func openInCursorApp(path: URL) throws {
        try shell("cursor \"\(path.path)\"")
    }
    
    private func getWorktreeStatus(path: String) throws -> String {
        let originalDir = fileManager.currentDirectoryPath
        fileManager.changeCurrentDirectoryPath(path)
        defer { fileManager.changeCurrentDirectoryPath(originalDir) }
        
        let status = try shellOutput("git status --porcelain")
        if status.isEmpty {
            return "Clean"
        } else {
            let lines = status.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return "\(lines.count) changed file(s)"
        }
    }
    
    private struct WorktreeInfo {
        let path: String
        let branch: String?
        let isBare: Bool
    }
    
    private func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?
        var isBare = false
        
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("worktree ") {
                if let path = currentPath {
                    worktrees.append(WorktreeInfo(path: path, branch: currentBranch, isBare: isBare))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
                isBare = false
            } else if line.hasPrefix("branch ") {
                let fullBranch = String(line.dropFirst("branch ".count))
                currentBranch = fullBranch.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "bare" {
                isBare = true
            }
        }
        
        if let path = currentPath {
            worktrees.append(WorktreeInfo(path: path, branch: currentBranch, isBare: isBare))
        }
        
        // Filter out the main worktree (first one is usually the main repo)
        return Array(worktrees.dropFirst())
    }
    
    // MARK: - Shell Execution

    private func shell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw WorktreeError.commandFailed(command, process.terminationStatus)
        }
    }
    
    private func shellOutput(_ command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Errors

enum WorktreeError: Error, CustomStringConvertible {
    case notInGitRepo
    case notFound(String)
    case noXcodeProject
    case commandFailed(String, Int32)
    
    var description: String {
        switch self {
        case .notInGitRepo:
            return "Not in a git repository"
        case .notFound(let branch):
            return "Worktree not found for branch: \(branch)"
        case .noXcodeProject:
            return "No Xcode project or workspace found in worktree"
        case .commandFailed(let cmd, let code):
            return "Command failed (\(code)): \(cmd)"
        }
    }
}
