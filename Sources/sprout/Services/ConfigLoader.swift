import Foundation
import TOMLDecoder

/// Loads and parses the Sprout configuration file
struct ConfigLoader {
    /// Default config file path
    static let defaultConfigPath = "~/.sprout/config.toml"

    /// Load configuration from the specified path
    /// - Parameter path: Path to config file (supports ~ expansion)
    /// - Returns: Parsed SproutConfig
    /// - Throws: ConfigError if file not found or parsing fails
    static func load(from path: String = defaultConfigPath) throws -> SproutConfig {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw ConfigError.fileNotFound(path)
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError.readFailed(path, error)
        }

        do {
            let decoder = TOMLDecoder()
            return try decoder.decode(SproutConfig.self, from: contents)
        } catch {
            throw ConfigError.parseFailed(path, error)
        }
    }
}

/// Errors that can occur during config loading
enum ConfigError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case readFailed(String, Error)
    case parseFailed(String, Error)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found: \(path)"
        case .readFailed(let path, let error):
            return "Failed to read config file \(path): \(error.localizedDescription)"
        case .parseFailed(let path, let error):
            return "Failed to parse config file \(path): \(error)"
        }
    }

    var exitCode: Int32 {
        1 // Config error
    }
}
