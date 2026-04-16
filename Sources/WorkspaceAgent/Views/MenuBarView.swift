import SwiftUI

/// The view shown when clicking the menu bar icon.
/// Compact: status, quick actions, and a button to open the full digest panel.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .foregroundStyle(.blue)
                Text("Workspace Agent")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            Divider()

            // Error banner
            if let error = appState.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Quick status
            if let digest = appState.digest {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last digest: \(digest.formattedTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        StatBadge(count: digest.replyNow.count, label: "Urgent", color: .red)
                        StatBadge(count: digest.reviewToday.count, label: "Review", color: .orange)
                        StatBadge(count: digest.canWait.count, label: "Later", color: .green)
                    }
                }
            } else if appState.lastError == nil {
                Text("No digest yet. Run your first triage below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Actions
            Button {
                Task { await runTriage() }
            } label: {
                Label(
                    appState.isTriaging ? "Triaging…" : "Run Email Triage",
                    systemImage: "envelope.open"
                )
            }
            .disabled(appState.isTriaging || appState.modelPath.isEmpty)

            Button {
                openWindow(id: "digest")
            } label: {
                Label("Open Digest Panel", systemImage: "rectangle.expand.vertical")
            }
            .disabled(appState.digest == nil)

            Button {
                openWindow(id: "activity-log")
            } label: {
                Label("Show Activity Log", systemImage: "list.bullet.rectangle")
            }

            Divider()

            // Engine status
            HStack {
                Circle()
                    .fill(engineColor)
                    .frame(width: 8, height: 8)
                Text(engineLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.modelName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusBadge: some View {
        switch appState.engineStatus {
        case .idle:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .generating:
            ProgressView()
                .controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var engineColor: Color {
        switch appState.engineStatus {
        case .idle: .gray
        case .loading: .yellow
        case .ready: .green
        case .generating: .blue
        case .error: .red
        }
    }

    private var engineLabel: String {
        switch appState.engineStatus {
        case .idle: "Engine idle"
        case .loading: "Loading model…"
        case .ready: "Model ready"
        case .generating(let p): "Generating: \(p)"
        case .error(let e): "Error: \(e)"
        }
    }

    private func runTriage() async {
        await appState.triageService.runTriage()
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
