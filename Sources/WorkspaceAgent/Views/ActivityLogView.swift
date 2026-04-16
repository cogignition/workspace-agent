import SwiftUI

/// Displays the in-app activity log with real-time updates.
struct ActivityLogView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Activity Log")
                    .font(.headline)
                Spacer()
                Button {
                    appState.logEntries.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                }
                .help("Clear log")
            }
            .padding(12)
            .borderBottom()

            // Log entries
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if appState.logEntries.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.plaintext")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No activity yet")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding()
                        } else {
                            ForEach(appState.logEntries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                            .padding(12)
                        }
                    }
                }
                .onChange(of: appState.logEntries.count) {
                    if let lastEntry = appState.logEntries.last {
                        scrollProxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("Activity Log")
        .frame(minWidth: 500, minHeight: 400)
    }

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Level indicator
            Circle()
                .fill(levelColor(entry.level))
                .frame(width: 8, height: 8)
                .padding(.top, 2)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.body)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: .secondary
        case .success: .green
        case .warning: .yellow
        case .error: .red
        }
    }
}

// MARK: - Border Helper

private struct BorderBottom: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Divider()
        }
    }
}

private extension View {
    func borderBottom() -> some View {
        modifier(BorderBottom())
    }
}
