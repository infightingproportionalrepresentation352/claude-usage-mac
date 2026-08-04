import Foundation

public enum Refresh {
    /// One poll: the API call and the transcript scan run concurrently, since
    /// one is network-bound and the other disk-bound.
    public static func snapshot(
        userAgent: String = UsageAPI.defaultUserAgent,
        force: Bool = false
    ) async -> Snapshot {
        async let usage = UsageAPI.shared.fetch(userAgent: userAgent, force: force)
        let stats = await TranscriptScanner.shared.scan(force: force)
        let result = await usage
        return Snapshot(usage: result.data, stats: stats,
                        error: result.error, stale: result.stale)
    }
}
