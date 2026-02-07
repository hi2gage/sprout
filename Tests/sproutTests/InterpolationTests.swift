import Testing
@testable import sprout

@Suite("Interpolation")
struct InterpolationTests {
    @Test("replaces known variables and preserves unknown", .tags(.unit))
    func interpolationBehavior() {
        let template = "Hello {name}, ticket {id}, keep {unknown}."
        let output = Interpolation.interpolate(template, with: ["name": "Ada", "id": "42"])
        #expect(output == "Hello Ada, ticket 42, keep {unknown}.")
    }
}
