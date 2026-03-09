import SwiftUI

@main
struct MBMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            if let icon = IconProvider.menuBarIcon() {
                Image(nsImage: icon)
            } else {
                Image(systemName: appState.statusIcon)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
