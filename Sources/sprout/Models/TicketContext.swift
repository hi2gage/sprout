import Foundation

/// Context fetched from a ticket source (Jira, GitHub, or raw prompt)
struct TicketContext {
    /// Raw identifier from input (e.g., "IOS-1234", "567")
    let ticketId: String

    /// Ticket title/summary
    let title: String?

    /// Full description body
    let description: String?

    /// Slugified title (lowercase, hyphens)
    let slug: String?

    /// Link back to the ticket
    let url: String?

    /// Ticket creator
    let author: String?

    /// Labels/tags
    let labels: [String]?

    /// Source branch name (for PRs that already have a branch)
    let sourceBranch: String?

    init(
        ticketId: String,
        title: String? = nil,
        description: String? = nil,
        slug: String? = nil,
        url: String? = nil,
        author: String? = nil,
        labels: [String]? = nil,
        sourceBranch: String? = nil
    ) {
        self.ticketId = ticketId
        self.title = title
        self.description = description
        self.slug = slug
        self.url = url
        self.author = author
        self.labels = labels
        self.sourceBranch = sourceBranch
    }

    /// Create a context from a raw prompt
    static func fromRawPrompt(_ prompt: String) -> TicketContext {
        let slug = Slugify.slugify(prompt)
        // Use first 8 chars of slug hash as ticket ID for raw prompts
        let hash = String(slug.hashValue.magnitude)
        let ticketId = "prompt-\(hash.prefix(8))"

        return TicketContext(
            ticketId: ticketId,
            title: prompt,
            description: prompt,
            slug: slug,
            url: nil,
            author: nil,
            labels: nil
        )
    }
}
