import Testing
@testable import sprout

@Suite("Input detector")
struct InputDetectorTests {
    @Test("detects Jira, GitHub issue/PR, and raw prompt", .tags(.unit))
    func inputDetection() {
        #expect(InputDetector.detect("IOS-123") == .jira("IOS-123"))
        #expect(InputDetector.detect("#88") == .github("88", repo: nil))
        #expect(InputDetector.detect("gh:99") == .github("99", repo: nil))
        #expect(InputDetector.detect("pr:77") == .githubPR("77", repo: nil))
        #expect(InputDetector.detect("https://github.com/org/repo/issues/12") == .github("12", repo: "org/repo"))
        #expect(InputDetector.detect("https://github.com/org/repo/pull/13") == .githubPR("13", repo: "org/repo"))
        #expect(InputDetector.detect("https://acme.atlassian.net/browse/IOS-7") == .jira("IOS-7"))
        #expect(InputDetector.detect("draft an architecture plan") == .rawPrompt("draft an architecture plan"))
    }
}
