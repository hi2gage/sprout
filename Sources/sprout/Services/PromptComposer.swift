import Foundation

/// Composes the final prompt from context and templates
struct PromptComposer {
    let config: PromptConfig?

    /// Compose the prompt and write it to a temp file
    /// - Returns: Path to the temp file
    func compose(context: TicketContext, variables: [String: String]) throws -> String {
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

        let fullPrompt = parts.joined(separator: "\n\n")

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "sprout-\(UUID().uuidString.prefix(8)).md"
        let tempFile = tempDir.appendingPathComponent(filename)

        try fullPrompt.write(to: tempFile, atomically: true, encoding: .utf8)

        return tempFile.path
    }
}
