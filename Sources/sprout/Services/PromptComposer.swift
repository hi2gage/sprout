import Foundation

/// Composes the final prompt from context and templates
struct PromptComposer {
    let config: PromptConfig?

    /// Compose the prompt and write it to ~/.sprout/prompts/
    /// - Returns: Path to the prompt file
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

        // Write to ~/.sprout/prompts/
        let promptsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sprout")
            .appendingPathComponent("prompts")

        // Create directory if needed
        try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)

        // Use branch name for filename
        let branch = variables["branch"] ?? "prompt"
        let filename = "\(branch).md"
        let promptFile = promptsDir.appendingPathComponent(filename)

        try fullPrompt.write(to: promptFile, atomically: true, encoding: .utf8)

        return promptFile.path
    }
}
