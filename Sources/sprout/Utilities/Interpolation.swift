import Foundation

/// Variable interpolation engine for templates
struct Interpolation {
    /// Interpolate variables into a template string
    /// Replaces {variable} patterns with values from the dictionary
    static func interpolate(_ template: String, with variables: [String: String]) -> String {
        var result = template

        // Replace each {key} with its value
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }

        return result
    }
}
