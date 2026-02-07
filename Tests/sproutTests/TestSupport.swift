import Foundation
import Testing

struct TemporaryDirectory {
    let url: URL

    init(prefix: String = "sprout-tests-", function: StaticString = #function) throws {
        let cleaned = String(describing: function)
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "_")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)\(cleaned)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

@discardableResult
func withTemporaryDirectory<T>(
    function: StaticString = #function,
    _ body: (URL) throws -> T
) throws -> T {
    let temp = try TemporaryDirectory(function: function)
    defer { temp.cleanup() }
    return try body(temp.url)
}

@discardableResult
func withTemporaryDirectory<T>(
    function: StaticString = #function,
    _ body: (URL) async throws -> T
) async throws -> T {
    let temp = try TemporaryDirectory(function: function)
    defer { temp.cleanup() }
    return try await body(temp.url)
}

extension Trait where Self == ConditionTrait {
    static func requires(executable tool: String) -> Self {
        enabled("requires '\(tool)' to be available on PATH") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["sh", "-lc", "command -v \"\(tool)\" >/dev/null 2>&1"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }
    }
}

@discardableResult
func runProcess(_ arguments: [String], cwd: URL? = nil) throws -> (Int32, String, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    if let cwd {
        process.currentDirectoryURL = cwd
    }

    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    try process.run()
    process.waitUntilExit()

    let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, outStr, errStr)
}
