import AppKit
import ServiceManagement
import SwiftUI

enum SettingsKey {
    static let warn = "warnThreshold"
    static let critical = "criticalThreshold"
    static let userAgent = "userAgent"
    static let menuBarMetric = "menuBarMetric"
    static let selectedProfile = "selectedProfile"
    static let autoCheckUpdates = "autoCheckUpdates"
}

struct SettingsView: View {
    @ObservedObject var poller: Poller

    @AppStorage(SettingsKey.warn) private var warn = 50.0
    @AppStorage(SettingsKey.critical) private var critical = 80.0
    @AppStorage(SettingsKey.userAgent) private var userAgent = UsageAPI.defaultUserAgent
    @AppStorage(SettingsKey.menuBarMetric) private var menuBarMetric = "session"
    @AppStorage(SettingsKey.selectedProfile) private var selectedProfile = ""
    @AppStorage(SettingsKey.autoCheckUpdates) private var autoCheckUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var extraPaths = ProfileStore.savedExtraPaths()

    var body: some View {
        Form {
            profileSection
            displaySection
            updatesSection

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
        .frame(width: 460)
        // Amber above red would colour everything red; keep the bands ordered.
        .onChange(of: warn) { _, new in if new > critical { critical = new } }
        .onChange(of: critical) { _, new in if new < warn { warn = new } }
        .onAppear(perform: reload)
    }

    // MARK: - Profiles

    private var profileSection: some View {
        Section {
            if poller.profiles.isEmpty {
                Text("No Claude Code data found")
                    .font(.callout)
                Text("Looked in ~/.claude and alongside it. If your config lives elsewhere — CLAUDE_CONFIG_DIR — add the folder below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Profile", selection: $selectedProfile) {
                    ForEach(poller.profiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .onChange(of: selectedProfile) { _, id in
                    guard let picked = poller.profiles.first(where: { $0.id == id }) else { return }
                    poller.select(picked)
                }
                if let active = poller.profiles.first(where: { $0.id == selectedProfile }) {
                    LabeledContent("Folder", value: active.configDir.path)
                        .font(.caption)
                    if let organization = active.organization {
                        LabeledContent("Organization",
                                       value: [organization, active.plan].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                    }
                }
            }

            // Folders added by hand are the only removable ones — the rest are
            // discovered, so "removing" them would just mean finding them again
            // on the next rescan.
            ForEach(extraPaths, id: \.self) { path in
                HStack {
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Remove") { removeFolder(path) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            HStack {
                Button("Add Folder…", action: addFolder)
                Spacer()
                Button("Rescan") { poller.rediscover() }
            }

            if poller.profiles.count > 1 {
                Text("Each profile is a separate Claude account. Limits, tokens and history are tracked independently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Profile")
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Claude Code config folder — the one containing a “projects” folder."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return }
        ProfileStore.addExtraPath(url.path)
        reload()
    }

    private func removeFolder(_ path: String) {
        ProfileStore.removeExtraPath(path)
        reload()
    }

    private func reload() {
        extraPaths = ProfileStore.savedExtraPaths()
        poller.rediscover()
    }

    // MARK: - Display

    private var displaySection: some View {
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
    }

    // MARK: - Updates

    private var updatesSection: some View {
        Section {
            LabeledContent("Version", value: AppVersion.current)
            HStack {
                // A silent success has to look like a success — without this the
                // feature is invisible until the day an update happens to exist.
                Text(updateStatus)
                    .font(.callout)
                    .foregroundStyle(poller.update == nil ? .secondary : .primary)
                Spacer()
                Button("Check Now", action: poller.checkForUpdates)
            }
            if let release = poller.update {
                Link("Open release notes", destination: release.url)
                    .font(.callout)
            }
            Toggle("Check automatically", isOn: $autoCheckUpdates)
            Text("Checks GitHub four times a day. Nothing is downloaded or installed — use `brew upgrade --cask claude-usage`, or the link above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Updates")
        }
    }

    private var updateStatus: String {
        if let release = poller.update {
            return "Version \(release.version) available"
        }
        guard let checked = poller.lastUpdateCheck else { return "Not checked yet" }
        let age = Int(Date().timeIntervalSince(checked))
        return age < 60 ? "Up to date — checked just now" : "Up to date"
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
