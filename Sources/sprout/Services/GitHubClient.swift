import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for fetching issues from GitHub API
struct GitHubClient {
    let repo: String

    init(repo: String) {
        self.repo = repo
    }

    init(config: GitHubConfig) {
        self.repo = config.repo ?? ""
    }

    /// Fetch an issue by its number
    func fetchIssue(_ issueNumber: String) async throws -> TicketContext {
        let token = try getToken()

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/issues/\(issueNumber)") else {
            throw SourceError.networkError(URLError(.badURL))
        }

        let data = try await makeRequest(url: url, token: token, errorId: "#\(issueNumber)")
        let issue = try JSONDecoder().decode(GitHubIssue.self, from: data)
        return issue.toTicketContext()
    }

    /// Fetch a pull request by its number
    func fetchPR(_ prNumber: String) async throws -> TicketContext {
        let token = try getToken()

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/pulls/\(prNumber)") else {
            throw SourceError.networkError(URLError(.badURL))
        }

        let data = try await makeRequest(url: url, token: token, errorId: "PR #\(prNumber)")
        let pr = try JSONDecoder().decode(GitHubPR.self, from: data)
        return pr.toTicketContext()
    }

    // MARK: - Private Helpers

    /// Get token from gh CLI, env var, or config
    private func getToken() throws -> String {
        // Try gh auth token first (uses gh CLI's stored credentials)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty {
                    return token
                }
            }
        } catch {
            // Fall through to env var check
        }

        // Fall back to environment variables
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            return token
        }

        throw SourceError.authFailed("GitHub: run 'gh auth login' or set GITHUB_TOKEN")
    }

    private func makeRequest(url: URL, token: String, errorId: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            throw SourceError.authFailed("GitHub")
        case 404:
            throw SourceError.ticketNotFound(errorId)
        default:
            throw SourceError.networkError(URLError(.badServerResponse))
        }
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

private struct GitHubPR: Decodable {
    let number: Int
    let title: String
    let body: String?
    let htmlUrl: String
    let user: GitHubUser?
    let labels: [GitHubLabel]?
    let head: GitHubBranch

    struct GitHubUser: Decodable {
        let login: String
    }

    struct GitHubLabel: Decodable {
        let name: String
    }

    struct GitHubBranch: Decodable {
        let ref: String
    }

    enum CodingKeys: String, CodingKey {
        case number, title, body, user, labels, head
        case htmlUrl = "html_url"
    }

    func toTicketContext() -> TicketContext {
        TicketContext(
            ticketId: "pr-\(number)",
            title: title,
            description: body,
            slug: Slugify.slugify(title),
            url: htmlUrl,
            author: user?.login,
            labels: labels?.map { $0.name },
            sourceBranch: head.ref
        )
    }
}
