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
