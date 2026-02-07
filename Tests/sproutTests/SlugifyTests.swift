import Testing
@testable import sprout

@Suite("Slugify")
struct SlugifyTests {
    @Test("normalizes text and punctuation", .tags(.unit))
    func slugifyBasic() {
        #expect(Slugify.slugify("Fix Login_Button NOW!!!") == "fix-login-button-now")
    }

    @Test("truncates long output", .tags(.unit))
    func slugifyTruncates() {
        let input = String(repeating: "abc_", count: 30)
        let slug = Slugify.slugify(input)
        #expect(slug.count <= 50)
        #expect(!slug.hasSuffix("-"))
    }
}
