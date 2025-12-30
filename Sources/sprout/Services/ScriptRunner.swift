import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

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

        let result = try await Subprocess.run(
            .path(FilePath("/bin/sh")),
            arguments: ["-c", script],
            output: .string(limit: 65536),
            error: .string(limit: 65536)
        )

        // Print output if any
        if let stdout = result.standardOutput {
            let trimmed = stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print(trimmed)
            }
        }

        if let stderr = result.standardError {
            let trimmed = stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                FileHandle.standardError.write(Data(trimmed.utf8))
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }

        guard result.terminationStatus.isSuccess else {
            let code: Int
            switch result.terminationStatus {
            case .exited(let exitCode):
                code = Int(exitCode)
            case .unhandledException(let exception):
                code = Int(exception)
            }
            throw ScriptError.executionFailed(code)
        }
    }
}
