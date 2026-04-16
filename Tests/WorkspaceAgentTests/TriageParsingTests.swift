import Testing
import Foundation
@testable import WorkspaceAgent

/// Tests EmailTriageService.parseTriageResult against real and edge-case model output.
struct TriageParsingTests {

    // Access the private method via a test-visible wrapper in EmailTriageService
    // (see EmailTriageService+Testable.swift)

    @Test func parsesCleanJSON() throws {
        let json = """
        {
          "rankedEmails": [
            { "emailId": "abc123", "priority": 1, "reason": "From CEO, needs reply.", "suggestedAction": "reply_now" },
            { "emailId": "def456", "priority": 4, "reason": "Newsletter.", "suggestedAction": "archive" }
          ],
          "summary": "One urgent item from leadership. Rest is noise."
        }
        """
        let result = try EmailTriageService.testParseTriageResult(json)
        #expect(result.rankedEmails.count == 2)
        #expect(result.rankedEmails[0].emailId == "abc123")
        #expect(result.rankedEmails[0].priority == 1)
        #expect(result.summary == "One urgent item from leadership. Rest is noise.")
    }

    @Test func stripsMarkdownFences() throws {
        let json = """
        ```json
        {
          "rankedEmails": [
            { "emailId": "x1", "priority": 2, "reason": "Action needed.", "suggestedAction": "review_today" }
          ],
          "summary": "One item to review."
        }
        ```
        """
        let result = try EmailTriageService.testParseTriageResult(json)
        #expect(result.rankedEmails.count == 1)
    }

    @Test func handlesLeadingAndTrailingText() throws {
        let json = """
        Here is the triage result:
        {
          "rankedEmails": [
            { "emailId": "y2", "priority": 3, "reason": "FYI update.", "suggestedAction": "fyi" }
          ],
          "summary": "Mostly informational."
        }
        Hope that helps!
        """
        let result = try EmailTriageService.testParseTriageResult(json)
        #expect(result.rankedEmails[0].emailId == "y2")
    }

    @Test func throwsOnInvalidJSON() {
        #expect(throws: (any Error).self) {
            try EmailTriageService.testParseTriageResult("not json at all")
        }
    }

    @Test func throwsOnWrongSchema() {
        #expect(throws: (any Error).self) {
            try EmailTriageService.testParseTriageResult(#"{"foo": "bar"}"#)
        }
    }
}
