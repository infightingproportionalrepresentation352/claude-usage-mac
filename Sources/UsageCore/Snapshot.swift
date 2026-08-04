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

    /// Must be prefixed with the Apple Team ID for a non-sandboxed host app to
    /// resolve the same container the sandboxed widget sees.
    public static let appGroup = "group.com.saeedkolivand.claude-usage"

    /// Both candidate locations, most-shared first.
    ///
    /// App Groups are a provisioning-profile capability and may need a paid
    /// developer account; Application Support always works but is only readable
    /// by a non-sandboxed widget. Writing both means the sandbox posture can be
    /// decided by flipping one entitlement, with no code change here.
    public static var locations: [URL] {
        var urls: [URL] = []
        if let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            urls.append(group.appendingPathComponent("state.json"))
        }
        if let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                support
                    .appendingPathComponent("ClaudeUsage", isDirectory: true)
                    .appendingPathComponent("state.json"))
        }
        return urls
    }

    /// Writes every location that accepts it. Succeeding at one is enough.
    @discardableResult
    public func write() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }

        var wrote = false
        for url in Self.locations {
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
