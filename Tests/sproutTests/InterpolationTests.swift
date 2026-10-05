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

    @Test("interpolates branch_type in branch template", .tags(.unit))
    func branchTypeInterpolation() {
        let template = "{branch_type}/{ticket_id}/{slug}"
        let output = Interpolation.interpolate(template, with: [
            "branch_type": "bugfix",
            "ticket_id": "IOS-1234",
            "slug": "fix-crash-on-login",
        ])
        #expect(output == "bugfix/IOS-1234/fix-crash-on-login")
    }
}
