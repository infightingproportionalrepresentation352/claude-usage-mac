import Foundation

/// Everything the widget needs, in one small file the host app writes.
///
/// The widget extension is sandboxed: it cannot read ~/.claude, cannot reach the
/// Keychain, and has no timer of its own. So it never fetches or parses anything
/// — it reads this and renders it.
public struct Snapshot: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var sessionPct: Double?
    public var sessionResetsAt: Date?
    public var weeklyPct: Double?
    public var weeklyResetsAt: Date?
    public var stats: LogStats
    /// Non-nil when the last refresh failed: "no-token", "token-expired",
    /// "http-401", "network", "bad-json".
    public var error: String?
    public var stale: Bool
    /// Carried here rather than read from UserDefaults, because the widget is
    /// sandboxed and cannot see the app's defaults without an App Group.
    public var warn: Double
    public var critical: Double
    /// Which profile these numbers belong to. Set only when the machine has more
    /// than one, so the ordinary single-profile case shows no extra chrome.
    public var profileLabel: String?

    public init(
        updatedAt: Date = Date(),
        usage: UsageData? = nil,
        stats: LogStats = LogStats(),
        error: String? = nil,
        stale: Bool = false,
        warn: Double = 50,
        critical: Double = 80
    ) {
        self.updatedAt = updatedAt
        self.warn = warn
        self.critical = critical
        self.sessionPct = usage?.fiveHour?.utilization
        self.sessionResetsAt = usage?.fiveHour?.resetsAt
        self.weeklyPct = usage?.sevenDay?.utilization
        self.weeklyResetsAt = usage?.sevenDay?.resetsAt
        self.stats = stats
        self.error = error
        self.stale = stale
    }

    public var sessionLevel: Level { Level.of(sessionPct, warn: warn, critical: critical) }
    public var weeklyLevel: Level { Level.of(weeklyPct, warn: warn, critical: critical) }
}

extension Snapshot {

    public static let appGroup = "group.com.saeedkolivand.claude-usage"
    public static let widgetBundleID = "com.saeedkolivand.claude-usage.widget"

    private static let relativePath = "ClaudeUsage/state.json"

    /// Where a reader looks, freshest wins.
    ///
    /// Inside the widget's sandbox `.applicationSupportDirectory` already
    /// resolves to its own container, which is the path the host writes to —
    /// so the widget needs no entitlement, no App Group, and no special case.
    public static var locations: [URL] {
        var urls: [URL] = []
        if let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            urls.append(group.appendingPathComponent(relativePath))
        }
        if let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(support.appendingPathComponent(relativePath))
        }
        return urls
    }

    /// The widget extension is sandboxed — macOS requires that of app extensions,
    /// and an unsandboxed one is simply never registered, so it never appears in
    /// the widget gallery. That rules out reading `~/.claude` directly.
    ///
    /// App Groups would be the textbook answer, but they're a
    /// provisioning-profile capability: with ad-hoc signing and no team,
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil.
    ///
    /// The host app, though, is *not* sandboxed. So it writes straight into the
    /// widget's container, which the widget then reads as its own Application
    /// Support. No paid account, no entitlement that needs provisioning.
    static var widgetContainer: URL? {
        // Inside a sandbox this would resolve to a nested path that doesn't
        // exist; harmless, because only the unsandboxed host ever writes.
        let data = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleID, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)

        // Only write into a container macOS has already created. Materializing
        // one ourselves would leave it without its container metadata, which can
        // stop the extension launching at all — worse than having no data yet.
        // It appears the first time the widget runs; the next poll fills it.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: data.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        return data
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    /// Writes every location that accepts it. Succeeding at one is enough.
    @discardableResult
    public func write() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }

        var wrote = false
        for url in Self.locations + [Self.widgetContainer].compactMap({ $0 }) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Atomic so the widget can never read a half-written file.
            if (try? data.write(to: url, options: .atomic)) != nil { wrote = true }
        }
        return wrote
    }

    /// Reads the freshest snapshot available. Not simply "first that exists" —
    /// if the entitlement changes between builds, one location goes stale while
    /// the other keeps updating, and the stale one would win on ordering alone.
    public static func read() -> Snapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return locations
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(Snapshot.self, from: $0) }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
