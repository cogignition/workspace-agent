import SwiftUI

@main
struct WorkspaceAgentApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar presence — always available
        MenuBarExtra("Workspace Agent", systemImage: "envelope.badge.shield.half.filled") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        // Floating digest panel — opened on demand
        Window("Morning Digest", id: "digest") {
            DigestPanelView()
                .environment(appState)
                .frame(minWidth: 480, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        // Settings
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
