import Foundation

/// Everything needed to watch one profile: its API client, its transcript
/// scanner, and its history file.
///
/// Grouping them is what keeps profiles from leaking into each other — the API
/// cache and the scanner's per-file offsets are both single-profile state, and a
/// shared instance would serve whichever account touched it last.
public actor ProfileMonitor {
    public let profile: Profile

    private let api: UsageAPI
    private let scanner: TranscriptScanner

    public init(profile: Profile) {
        self.profile = profile
        self.api = UsageAPI(profile: profile)
        self.scanner = TranscriptScanner(profile: profile)
    }

    /// One poll. The API call and the transcript scan run concurrently, since one
    /// is network-bound and the other disk-bound.
    public func snapshot(
        userAgent: String = UsageAPI.defaultUserAgent,
        force: Bool = false,
        warn: Double = 50,
        critical: Double = 80,
        label: String? = nil
    ) async -> Snapshot {
        async let usage = api.fetch(userAgent: userAgent, force: force)
        let stats = await scanner.scan(force: force)
        let result = await usage

        var snapshot = Snapshot(usage: result.data, stats: stats,
                                error: result.error, stale: result.stale,
                                warn: warn, critical: critical)
        snapshot.profileLabel = label
        return snapshot
    }

    /// Reads every transcript, not just the scan window, to seed history on a
    /// fresh install. Runs once ever, and callers fire it after the first refresh
    /// so the UI isn't waiting on gigabytes.
    public func backfillHistory() async {
        await scanner.backfillHistory()
    }
}
