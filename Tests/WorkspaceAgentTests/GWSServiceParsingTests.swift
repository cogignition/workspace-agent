import Testing
import Foundation
@testable import WorkspaceAgent

/// Tests GWSService.parseEmails against real gws +triage JSON output shapes.
struct GWSServiceParsingTests {

    let service = GWSService()

    // MARK: - +triage wrapper format

    @Test func parsesTriageWrapperFormat() async throws {
        let json = """
        {
          "messages": [
            {
              "date": "Thu, 16 Apr 2026 00:40:26 +0000 (UTC)",
              "from": "Grafana <alerts@example.com>",
              "id": "abc123",
              "subject": "Storage Alert Detected"
            },
            {
              "date": "Wed, 15 Apr 2026 22:34:22 +0000",
              "from": "Slack <notification@slack.com>",
              "id": "def456",
              "subject": "New messages in #general"
            }
          ],
          "query": "is:unread",
          "resultSizeEstimate": 201
        }
        """

        let emails = try await service.parseEmails(from: json)
        #expect(emails.count == 2)
        #expect(emails[0].id == "abc123")
        #expect(emails[0].subject == "Storage Alert Detected")
        #expect(emails[0].from == "Grafana <alerts@example.com>")
        #expect(emails[1].id == "def456")
    }

    @Test func parsesBareArrayFormat() async throws {
        let json = """
        [
          {
            "date": "Thu, 16 Apr 2026 00:40:26 +0000",
            "from": "Boss <boss@example.com>",
            "id": "xyz789",
            "subject": "Urgent: please review"
          }
        ]
        """
        let emails = try await service.parseEmails(from: json)
        #expect(emails.count == 1)
        #expect(emails[0].id == "xyz789")
    }

    @Test func stripsKeyringLogPrefix() async throws {
        // gws sometimes emits "Using keyring backend: keyring\n" before the JSON
        let json = """
        Using keyring backend: keyring
        {
          "messages": [
            {
              "date": "Thu, 16 Apr 2026 00:40:26 +0000",
              "from": "Test <test@example.com>",
              "id": "aaa111",
              "subject": "Hello"
            }
          ],
          "query": "is:unread",
          "resultSizeEstimate": 1
        }
        """
        let emails = try await service.parseEmails(from: json)
        #expect(emails.count == 1)
        #expect(emails[0].id == "aaa111")
    }

    @Test func emptyMessagesReturnsEmptyArray() async throws {
        let json = """
        { "messages": [], "query": "is:unread", "resultSizeEstimate": 0 }
        """
        let emails = try await service.parseEmails(from: json)
        #expect(emails.isEmpty)
    }

    @Test func missingOptionalFieldsDefaultGracefully() async throws {
        // snippet and threadId are optional — should not throw
        let json = """
        {
          "messages": [
            { "id": "min1", "from": "a@b.com", "subject": "Hi", "date": "Mon, 1 Jan 2026 00:00:00 +0000" }
          ],
          "query": "is:unread",
          "resultSizeEstimate": 1
        }
        """
        let emails = try await service.parseEmails(from: json)
        #expect(emails.count == 1)
        #expect(emails[0].snippet == "")
        #expect(emails[0].threadId == nil)
        #expect(emails[0].isUnread == true)
    }
}
