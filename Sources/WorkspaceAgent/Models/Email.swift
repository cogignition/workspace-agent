import Foundation

/// Represents an email fetched via `gws gmail`.
/// Mirrors the JSON structure returned by `gws gmail messages list --format json`.
struct Email: Identifiable, Codable, Sendable {
    let id: String
    let threadId: String
    let subject: String
    let from: String
    let to: String
    let date: Date
    let snippet: String
    let labelIds: [String]
    let isUnread: Bool

    /// Priority assigned by the local model during triage (1 = highest)
    var priority: Int?
    /// One-line reason the model gave for the priority ranking
    var triageReason: String?

    enum CodingKeys: String, CodingKey {
        case id, threadId, subject, from, to, date, snippet, labelIds, isUnread
        case priority, triageReason
    }
}

/// The structured output the model produces when triaging a batch of emails.
struct TriageResult: Codable, Sendable {
    let rankedEmails: [TriagedEmail]
    let summary: String

    struct TriagedEmail: Codable, Sendable {
        let emailId: String
        let priority: Int
        let reason: String
        let suggestedAction: SuggestedAction
    }

    enum SuggestedAction: String, Codable, Sendable {
        case replyNow = "reply_now"
        case reviewToday = "review_today"
        case delegate = "delegate"
        case archive = "archive"
        case fyi = "fyi"
    }
}
