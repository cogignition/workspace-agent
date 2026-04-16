import SwiftUI

/// The detachable floating panel showing the full morning digest.
struct DigestPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let digest = appState.digest {
                digestContent(digest)
            } else if appState.isTriaging {
                triagingView
            } else {
                emptyState
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Digest Content

    @ViewBuilder
    private func digestContent(_ digest: EmailDigest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header(digest)

                // Summary from the model
                if !digest.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("AI Summary", systemImage: "sparkles")
                            .font(.subheadline.bold())
                        Text(digest.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                // Urgent — reply now
                if !digest.replyNow.isEmpty {
                    emailSection(
                        title: "Reply Now",
                        icon: "exclamationmark.circle.fill",
                        color: .red,
                        emails: digest.replyNow
                    )
                }

                // Review today
                if !digest.reviewToday.isEmpty {
                    emailSection(
                        title: "Review Today",
                        icon: "clock.fill",
                        color: .orange,
                        emails: digest.reviewToday
                    )
                }

                // Can wait
                if !digest.canWait.isEmpty {
                    emailSection(
                        title: "Can Wait",
                        icon: "tray.fill",
                        color: .green,
                        emails: digest.canWait
                    )
                }

                // Footer
                footer(digest)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func header(_ digest: EmailDigest) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Morning Digest")
                    .font(.title2.bold())
                Text("\(digest.totalEmails) emails triaged at \(digest.formattedTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Token Cost")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(digest.tokenCost)
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func emailSection(title: String, icon: String, color: Color, emails: [Email]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.bold())
                Text("(\(emails.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(emails) { email in
                EmailRowView(email: email)
            }
        }
    }

    @ViewBuilder
    private func footer(_ digest: EmailDigest) -> some View {
        HStack {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
            Text("Processed locally via \(appState.modelName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("No data sent to external APIs")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - Empty / Loading States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Digest Yet", systemImage: "envelope.open")
        } description: {
            Text("Click \"Run Email Triage\" from the menu bar to generate your morning digest.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var triagingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Triaging emails…")
                .font(.headline)

            if case .generating(let progress) = appState.engineStatus {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
