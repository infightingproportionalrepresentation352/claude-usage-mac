import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var poller = Poller()

    var body: some Scene {
        MenuBarExtra {
            MenuView(snapshot: poller.snapshot,
                     isRefreshing: poller.isRefreshing,
                     update: poller.update,
                     refresh: poller.refreshNow)
        } label: {
            // Monospaced digits stop the menu bar shuffling as the number changes.
            Text(poller.menuBarTitle).monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
