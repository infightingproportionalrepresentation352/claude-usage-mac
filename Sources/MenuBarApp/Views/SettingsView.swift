import ServiceManagement
import SwiftUI

enum SettingsKey {
    static let warn = "warnThreshold"
    static let critical = "criticalThreshold"
    static let userAgent = "userAgent"
    static let menuBarMetric = "menuBarMetric"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.warn) private var warn = 50.0
    @AppStorage(SettingsKey.critical) private var critical = 80.0
    @AppStorage(SettingsKey.userAgent) private var userAgent = UsageAPI.defaultUserAgent
    @AppStorage(SettingsKey.menuBarMetric) private var menuBarMetric = "session"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Picker("Menu bar shows", selection: $menuBarMetric) {
                    Text("5-hour session").tag("session")
                    Text("Weekly").tag("weekly")
                }
                Slider(value: $warn, in: 10...95, step: 5) {
                    Text("Amber above")
                } minimumValueLabel: {
                    Text("10%").font(.caption)
                } maximumValueLabel: {
                    Text("95%").font(.caption)
                }
                LabeledContent("", value: "\(Int(warn))%")
                Slider(value: $critical, in: 10...100, step: 5) {
                    Text("Red above")
                } minimumValueLabel: {
                    Text("10%").font(.caption)
                } maximumValueLabel: {
                    Text("100%").font(.caption)
                }
                LabeledContent("", value: "\(Int(critical))%")
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                TextField("User-Agent", text: $userAgent)
                Text("The usage endpoint rate-limits clients that don't identify as Claude Code. Change this only if the version string goes stale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        // Amber above red would colour everything red; keep the bands ordered.
        .onChange(of: warn) { _, new in if new > critical { critical = new } }
        .onChange(of: critical) { _, new in if new < warn { warn = new } }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            // Unsigned builds can't register a login item; say so rather than
            // silently flipping the toggle back.
            launchError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
