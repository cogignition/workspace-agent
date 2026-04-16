import SwiftUI

/// A single email row in the digest, showing sender, subject, triage reason, and suggested action.
struct EmailRowView: View {
    let email: Email

    var body: some View {
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
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
