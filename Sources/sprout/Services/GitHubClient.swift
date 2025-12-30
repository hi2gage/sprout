import Foundation

/// Client for fetching issues from GitHub API
struct GitHubClient {
    let repo: String
    let token: String?

    /// Initialize with just a repo (token from env)
    init(repo: String) {
        self.repo = repo
        self.token = nil
    }

    /// Initialize with config (for backwards compatibility)
    init(config: GitHubConfig) {
        self.repo = config.repo ?? ""
        self.token = config.token
    }

    /// Fetch an issue by its number
    func fetchIssue(_ issueNumber: String) async throws -> TicketContext {
        // Get token from environment or init
        // Use SPROUT_GITHUB_TOKEN to avoid conflicts with gh CLI
        guard let token = ProcessInfo.processInfo.environment["SPROUT_GITHUB_TOKEN"]
            ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
            ?? token else {
            throw SourceError.authFailed("GitHub: SPROUT_GITHUB_TOKEN or GITHUB_TOKEN not set")
        }

        // Build URL
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/issues/\(issueNumber)") else {
            throw SourceError.networkError(URLError(.badURL))
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw SourceError.authFailed("GitHub")
        case 404:
            throw SourceError.ticketNotFound("#\(issueNumber)")
        default:
            throw SourceError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        // Parse response
        let issue = try JSONDecoder().decode(GitHubIssue.self, from: data)
        return issue.toTicketContext()
    }
}

// MARK: - GitHub API Response Models

private struct GitHubIssue: Decodable {
    let number: Int
    let title: String
    let body: String?
    let htmlUrl: String
    let user: GitHubUser?
    let labels: [GitHubLabel]?

    struct GitHubUser: Decodable {
        let login: String
    }

    struct GitHubLabel: Decodable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case number, title, body, user, labels
        case htmlUrl = "html_url"
    }

    func toTicketContext() -> TicketContext {
        TicketContext(
            ticketId: String(number),
            title: title,
            description: body,
            slug: Slugify.slugify(title),
            url: htmlUrl,
            author: user?.login,
            labels: labels?.map { $0.name }
        )
    }
}
