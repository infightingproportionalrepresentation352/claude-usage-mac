import Foundation

/// Every profile's snapshot in one file.
///
/// Widgets are configured individually, so any of them may be scoped to any
/// profile — which means the host has to poll them all and publish them all.
/// `Snapshot` itself is unchanged: it stays the per-profile payload the views
/// already render, and this only wraps it.
public struct SnapshotBundle: Codable, Sendable, Equatable {
    public var updatedAt: Date
    /// Keyed by `Profile.id`, which is the config directory path.
    public var profiles: [String: Snapshot]
    /// Ordered, default first — the widget's configuration picker reads this
    /// rather than enumerating directories, which its sandbox forbids.
    public var profileList: [Profile]
    public var defaultProfileID: String?

    public init(updatedAt: Date = Date(),
                profiles: [String: Snapshot] = [:],
                profileList: [Profile] = [],
                defaultProfileID: String? = nil) {
        self.updatedAt = updatedAt
        self.profiles = profiles
        self.profileList = profileList
        self.defaultProfileID = defaultProfileID
    }

    /// Exactly the named profile, or nil.
    ///
    /// Deliberately does not fall back: a widget configured for one account and
    /// quietly showing another's numbers is worse than one that says it can't
    /// find the account. Callers decide, because "unconfigured" and "configured
    /// but gone" deserve different answers.
    public func snapshot(forExactly profileID: String) -> Snapshot? {
        profiles[profileID]
    }

    public func profile(forExactly profileID: String) -> Profile? {
        profileList.first { $0.id == profileID }
    }

    public var defaultProfile: Profile? {
        profileList.first { $0.id == defaultProfileID } ?? profileList.first
    }

    public var defaultSnapshot: Snapshot? {
        defaultProfile.flatMap { profiles[$0.id] }
    }
}

extension SnapshotBundle {
    private static let filename = "bundle.json"

    /// Alongside the single-profile `state.json`, which stays as it is so an
    /// older widget build keeps working after the app updates.
    public static var locations: [URL] {
        Snapshot.locations.map {
            $0.deletingLastPathComponent().appendingPathComponent(filename)
        }
    }

    static var widgetContainer: URL? {
        Snapshot.widgetContainer?
            .deletingLastPathComponent()
            .appendingPathComponent(filename)
    }

    @discardableResult
    public func write() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }

        var wrote = false
        for url in Self.locations + [Self.widgetContainer].compactMap({ $0 }) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil { wrote = true }
        }
        return wrote
    }

    public static func read() -> SnapshotBundle? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (locations + [widgetContainer].compactMap { $0 })
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(SnapshotBundle.self, from: $0) }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
