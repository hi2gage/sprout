import Foundation

/// Utilities for generating URL-safe slugs
struct Slugify {
    /// Convert a string to a URL-safe slug
    /// - Parameter input: The string to slugify
    /// - Returns: Lowercase string with spaces and special chars replaced by hyphens
    static func slugify(_ input: String) -> String {
        let lowercased = input.lowercased()

        // Replace spaces and underscores with hyphens
        var result = lowercased.replacingOccurrences(of: " ", with: "-")
        result = result.replacingOccurrences(of: "_", with: "-")

        // Remove non-alphanumeric characters except hyphens
        result = result.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
        }.map { String($0) }.joined()

        // Collapse multiple hyphens into one
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }

        // Trim leading/trailing hyphens
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Limit length
        if result.count > 50 {
            result = String(result.prefix(50))
            // Don't end with a hyphen
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return result
    }
}
