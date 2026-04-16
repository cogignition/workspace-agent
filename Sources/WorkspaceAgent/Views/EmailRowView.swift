import SwiftUI

/// A single email row in the digest, showing sender, subject, triage reason, and suggested action.
/// Clicking opens the email directly in Gmail.
struct EmailRowView: View {
    let email: Email
    @State private var isHovered = false

    var body: some View {
        Button(action: openInGmail) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(email.from)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    Text(email.date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered ? 1 : 0)
                }

                Text(email.subject)
                    .font(.subheadline)
                    .lineLimit(2)

                if let reason = email.triageReason {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color(.windowBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open in Gmail")
    }

    private func openInGmail() {
        // Gmail deep link using the hex message ID
        let urlString = "https://mail.google.com/mail/u/0/#inbox/\(email.id)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
