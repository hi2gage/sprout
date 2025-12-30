import Foundation

/// Represents the detected source type for the input
enum InputSource: CustomStringConvertible {
    /// Jira ticket (e.g., "IOS-1234")
    case jira(String)

    /// GitHub issue number (e.g., "567")
    case github(String)

    /// Raw prompt text
    case rawPrompt(String)

    var description: String {
        switch self {
        case .jira(let id):
            return "Jira(\(id))"
        case .github(let number):
            return "GitHub(#\(number))"
        case .rawPrompt(let prompt):
            let truncated = prompt.prefix(30)
            return "RawPrompt(\"\(truncated)...\")"
        }
    }
}
