import Foundation

/// Composes the final prompt from context and templates
struct PromptComposer {
    let config: PromptConfig?

    /// Compose the prompt content
    /// - Returns: The composed prompt string
    func composeContent(context: TicketContext, variables: [String: String]) -> String {
        var parts: [String] = []

        // Add prefix if configured
        if let prefix = config?.prefix {
            let interpolated = Interpolation.interpolate(prefix, with: variables)
            parts.append(interpolated.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Compose main body from template
        let template = config?.resolvedTemplate ?? "# {title}\n\n{description}"
        let body = Interpolation.interpolate(template, with: variables)
        parts.append(body.trimmingCharacters(in: .whitespacesAndNewlines))

        // Add suffix if configured
        if let suffix = config?.suffix {
            let interpolated = Interpolation.interpolate(suffix, with: variables)
            parts.append(interpolated.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return parts.joined(separator: "\n\n")
    }
}
