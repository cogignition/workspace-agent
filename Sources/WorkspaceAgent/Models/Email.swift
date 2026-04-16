import Foundation

/// Represents an email fetched via `gws gmail +triage --format json`.
/// Fields match the +triage JSON output: id, from, subject, date.
struct Email: Identifiable, Codable, Sendable {
    let id: String
    let subject: String
    let from: String
    let date: String      // kept as raw string — +triage returns RFC 2822 format
    let snippet: String   // not returned by +triage; populated empty for now

    // Optional fields for richer data if fetched individually
    let threadId: String?
    let isUnread: Bool

    /// Priority assigned by the local model during triage (1 = highest)
    var priority: Int?
    /// One-line reason the model gave for the priority ranking
    var triageReason: String?

    enum CodingKeys: String, CodingKey {
        case id, subject, from, date, snippet, threadId, isUnread
        case priority, triageReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        from = try container.decode(String.self, forKey: .from)
        date = try container.decode(String.self, forKey: .date)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        isUnread = try container.decodeIfPresent(Bool.self, forKey: .isUnread) ?? true
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        triageReason = try container.decodeIfPresent(String.self, forKey: .triageReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subject, forKey: .subject)
        try container.encode(from, forKey: .from)
        try container.encode(date, forKey: .date)
        try container.encode(snippet, forKey: .snippet)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encode(isUnread, forKey: .isUnread)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(triageReason, forKey: .triageReason)
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
