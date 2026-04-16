import Foundation

/// A complete morning digest produced by the triage pipeline.
struct EmailDigest: Identifiable, Sendable {
    let id = UUID()
    let generatedAt: Date
    let totalEmails: Int
    let rankedEmails: [Email]
    let summary: String
    let tokenCost: String = "$0.00"  // Always zero — local inference

    /// Emails grouped by suggested action
    var replyNow: [Email] { rankedEmails.filter { $0.priority == 1 } }
    var reviewToday: [Email] { rankedEmails.filter { $0.priority == 2 } }
    var canWait: [Email] { rankedEmails.filter { ($0.priority ?? 99) >= 3 } }

    /// Formatted generation time for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: generatedAt)
    }
}
