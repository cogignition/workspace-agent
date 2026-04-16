import SwiftUI

/// Settings pane — model path, gws binary, triage preferences.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView {
            // MARK: General Tab
            Form {
                Section("Google Workspace CLI") {
                    LabeledContent("gws path") {
                        TextField("", text: $state.gwsPath)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Path to the gws binary. Install from github.com/nicholasgasior/gws.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Triage") {
                    Stepper("Max emails: \(state.maxEmails)", value: $state.maxEmails, in: 10...200, step: 10)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            // MARK: Model Tab
            Form {
                Section("Local Model") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model file path (.gguf)")
                            .font(.subheadline)
                        TextField("", text: $state.modelPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.data]
                            panel.canChooseDirectories = false
                            panel.nameFieldStringValue = "*.gguf"
                            if panel.runModal() == .OK, let url = panel.url {
                                state.modelPath = url.path(percentEncoded: false)
                            }
                        }
                        Spacer()
                        Text(state.engineStatus.isReady ? "Loaded ✓" : "Not loaded")
                            .font(.caption)
                            .foregroundStyle(state.engineStatus.isReady ? .green : .secondary)
                    }

                    Text("Recommended: Gemma 3 12B Q8 (~12 GB). Download with:\nhuggingface-cli download bartowski/google_gemma-3-12b-it-GGUF --include \"*Q8_0*\" --local-dir ~/models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Section("Context Window") {
                    Picker("Context size", selection: $state.contextSize) {
                        Text("4 096 tokens  (fastest, least RAM)").tag(4096)
                        Text("8 192 tokens  (default)").tag(8192)
                        Text("16 384 tokens  (longer batches)").tag(16384)
                        Text("32 768 tokens  (large inbox)").tag(32768)
                    }
                    Text("Larger context lets the model see more emails at once and reduces truncation, at the cost of extra RAM. Reload the model after changing this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Model Memory") {
                    Picker("Keep loaded for", selection: $state.modelUnloadTimeout) {
                        Text("Unload immediately").tag(TimeInterval(0))
                        Text("1 minute").tag(TimeInterval(60))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("15 minutes").tag(TimeInterval(900))
                        Text("30 minutes").tag(TimeInterval(1800))
                    }
                    Text("Set to \"Unload immediately\" for cron or single-run usage to free ~12 GB RAM after each triage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Model", systemImage: "cpu") }

            // MARK: Advanced Tab
            Form {
                Section("Custom Triage Prompt") {
                    TextEditor(text: $state.triagePromptOverride)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .border(.quaternary)

                    Text("Leave empty to use the default prompt. Use {emails_json} as the placeholder for email data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 500, height: 360)
    }
}
