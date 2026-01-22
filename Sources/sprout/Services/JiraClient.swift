import Foundation

/// Client for fetching tickets from Jira API
struct JiraClient {
    let config: JiraConfig

    /// Fetch a ticket by its ID (e.g., "IOS-1234")
    func fetchTicket(_ ticketId: String) async throws -> TicketContext {
        // Get credentials from environment (like fetch CLI does) or fall back to config
        let env = ProcessInfo.processInfo.environment

        guard let token = env["JIRA_TOKEN"] ?? env["JIRA_API_TOKEN"] ?? config.token else {
            throw SourceError.authFailed("Jira: JIRA_TOKEN or JIRA_API_TOKEN not set")
        }

        guard let email = env["JIRA_EMAIL"] ?? env["JIRA_USER"] ?? Optional(config.email) else {
            throw SourceError.authFailed("Jira: JIRA_EMAIL not set")
        }

        // Build URL - use env var or config for base URL
        let baseUrl = (env["JIRA_BASE_URL"] ?? config.baseUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseUrl)/rest/api/3/issue/\(ticketId)") else {
            throw SourceError.networkError(URLError(.badURL))
        }

        // Build request with Basic auth
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = "\(email):\(token)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw SourceError.authFailed("Jira")
        case 404:
            throw SourceError.ticketNotFound(ticketId)
        default:
            throw SourceError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        // Parse response
        let issue = try JSONDecoder().decode(JiraIssue.self, from: data)
        return issue.toTicketContext()
    }
}

// MARK: - Jira API Response Models

private struct JiraIssue: Decodable {
    let key: String
    let fields: JiraFields

    struct JiraFields: Decodable {
        let summary: String?
        let description: JiraDescription?
        let creator: JiraUser?
        let labels: [String]?

        struct JiraDescription: Decodable {
            let content: [JiraContent]?

            struct JiraContent: Decodable {
                let content: [JiraTextContent]?

                struct JiraTextContent: Decodable {
                    let text: String?
                }
            }

            var plainText: String {
                content?.compactMap { outer in
                    outer.content?.compactMap { $0.text }.joined()
                }.joined(separator: "\n") ?? ""
            }
        }

        struct JiraUser: Decodable {
            let displayName: String?
        }
    }

    func toTicketContext() -> TicketContext {
        TicketContext(
            ticketId: key,
            title: fields.summary,
            description: fields.description?.plainText,
            slug: fields.summary.map { Slugify.slugify($0) },
            url: nil, // Could compute from base URL if needed
            author: fields.creator?.displayName,
            labels: fields.labels
        )
    }
}
