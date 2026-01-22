import Foundation

/// Executes the launch script
struct ScriptRunner {
    /// Execute a shell script
    func execute(_ script: String, verbose: Bool) async throws {
        if verbose {
            print("Executing script:")
            print("---")
            print(script)
            print("---")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        // Print output if any
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        if let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outStr.isEmpty {
            print(outStr)
        }

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        if let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !errStr.isEmpty {
            FileHandle.standardError.write(Data(errStr.utf8))
            FileHandle.standardError.write(Data("\n".utf8))
        }

        guard process.terminationStatus == 0 else {
            throw ScriptError.executionFailed(Int(process.terminationStatus))
        }
    }
}
