import Foundation
import SwiftUI
import WidgetKit

/// Owns the refresh loop. The widget never polls anything itself — this writes
/// the snapshot file and tells WidgetKit to reload.
@MainActor
final class Poller: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var update: ReleaseInfo?
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var lastUpdateCheck: Date?

    @AppStorage(SettingsKey.warn) private var warn = 50.0
    @AppStorage(SettingsKey.critical) private var critical = 80.0
    @AppStorage(SettingsKey.userAgent) private var userAgent = UsageAPI.defaultUserAgent
    @AppStorage(SettingsKey.menuBarMetric) private var menuBarMetric = "session"
    @AppStorage(SettingsKey.selectedProfile) private var selectedProfile = ""
    @AppStorage(SettingsKey.autoCheckUpdates) private var autoCheckUpdates = true

    private static let interval: Duration = .seconds(60)
    private var loop: Task<Void, Never>?
    private var monitor: ProfileMonitor?

    /// What the menu bar itself shows. Deliberately text-only: menu bar items
    /// are rendered as template images, so a coloured dot would come out grey.
    /// The bang is the one signal that survives monochrome.
    var menuBarTitle: String {
        guard let snapshot else { return "··" }
        let metric: Metric = menuBarMetric == "weekly" ? .weekly : .session
        guard let pct = snapshot.pct(metric) else { return "--" }
        let text = Format.percent(pct)
        return snapshot.level(metric) == .critical ? "! \(text)" : text
    }

    /// Starts immediately: the menu bar title must be populated before the user
    /// ever opens the menu, so this can't wait for a view's onAppear.
    ///
    /// `autostart: false` builds an inert one for previews and snapshot tests —
    /// no discovery against the real home directory, no poll loop.
    init(autostart: Bool = true, profiles: [Profile] = [], snapshot: Snapshot? = nil) {
        guard autostart else {
            self.profiles = profiles
            self.snapshot = snapshot
            return
        }
        rediscover()
        start()
    }

    /// Rebuilds the profile list, and the monitor if the active profile changed.
    /// Cheap enough to run on every settings visit — it stats a handful of
    /// directories and parses one small JSON per profile.
    func rediscover() {
        profiles = ProfileStore.discover(extraPaths: ProfileStore.savedExtraPaths())
        let active = profiles.first { $0.id == selectedProfile } ?? profiles.first

        guard let active else {
            monitor = nil
            snapshot = nil
            return
        }
        if selectedProfile != active.id { selectedProfile = active.id }
        guard monitor?.profile.id != active.id else { return }

        monitor = ProfileMonitor(profile: active)
        // Nothing stale must sit under a newly selected profile's name.
        snapshot = nil
        Task { [monitor] in await monitor?.backfillHistory() }
    }

    func select(_ profile: Profile) {
        selectedProfile = profile.id
        rediscover()
        refreshNow()
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refreshNow() {
        Task { await refresh(force: true) }
    }

    func checkForUpdates() {
        Task {
            update = await UpdateChecker.shared.check(
                currentVersion: AppVersion.current, force: true)
            lastUpdateCheck = Date()
        }
    }

    private func refresh(force: Bool = false) async {
        // A manual tap while the first (slow) scan is still running would queue a
        // second full read of the same gigabytes.
        guard !isRefreshing, let monitor else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let fresh = await monitor.snapshot(
            userAgent: userAgent, force: force, warn: warn, critical: critical,
            label: profiles.count > 1 ? monitor.profile.displayName : nil)
        snapshot = fresh
        fresh.write()
        WidgetCenter.shared.reloadAllTimelines()

        guard autoCheckUpdates else { return }
        // Rate-limited internally to four times a day, so calling it every poll
        // costs nothing.
        update = await UpdateChecker.shared.check(currentVersion: AppVersion.current)
        lastUpdateCheck = Date()
    }
}
