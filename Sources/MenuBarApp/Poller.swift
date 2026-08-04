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

    @AppStorage(SettingsKey.warn) private var warn = 50.0
    @AppStorage(SettingsKey.critical) private var critical = 80.0
    @AppStorage(SettingsKey.userAgent) private var userAgent = UsageAPI.defaultUserAgent
    @AppStorage(SettingsKey.menuBarMetric) private var menuBarMetric = "session"

    private static let interval: Duration = .seconds(60)
    private var loop: Task<Void, Never>?

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
    init() {
        start()
        // After the first refresh has the UI populated, seed history from the
        // full transcript archive. It reads gigabytes and runs once ever; the
        // scanner actor serializes it behind the poll already in flight.
        Task { await TranscriptScanner.shared.backfillHistory() }
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

    private func refresh(force: Bool = false) async {
        // A manual tap while the first (slow) scan is still running would queue a
        // second full read of the same gigabytes.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let fresh = await Refresh.snapshot(
            userAgent: userAgent, force: force, warn: warn, critical: critical)
        snapshot = fresh
        fresh.write()
        WidgetCenter.shared.reloadAllTimelines()

        // Rate-limited internally to four times a day, so calling it every poll
        // costs nothing.
        update = await UpdateChecker.shared.check(currentVersion: AppVersion.current)
    }
}
