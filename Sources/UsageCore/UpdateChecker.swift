import Foundation

public struct ReleaseInfo: Codable, Sendable, Equatable {
    public var version: String
    public var url: URL
}

/// Checks GitHub for a newer release and reports it. Deliberately not an
/// installer: Sparkle would mean a dependency, a hosted appcast, an EdDSA
/// keypair, and an updater that wants a properly signed app. A link in the menu
/// costs none of that, and `brew upgrade` handles the rest for cask users.
public actor UpdateChecker {
    public static let shared = UpdateChecker()

    static let endpoint = URL(
        string: "https://api.github.com/repos/saeedkolivand/claude-usage-mac/releases/latest")!

    /// Unauthenticated GitHub allows 60 requests an hour per IP. Four a day is
    /// well clear of that even with several machines behind one address.
    private static let interval: TimeInterval = 6 * 3600

    private var lastCheck: Date = .distantPast
    private var found: ReleaseInfo?

    /// Returns a release only when it is newer than `currentVersion`.
    public func check(currentVersion: String, force: Bool = false) async -> ReleaseInfo? {
        if !force, Date().timeIntervalSince(lastCheck) < Self.interval { return found }
        lastCheck = Date()

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("claude-usage-mac", forHTTPHeaderField: "User-Agent")

        guard
            let (body, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
            let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let tag = root["tag_name"] as? String,
            let page = (root["html_url"] as? String).flatMap(URL.init(string:))
        else {
            return found  // an offline check is not news; keep whatever we knew
        }

        // A draft or prerelease shouldn't nag people running the stable build.
        if root["draft"] as? Bool == true || root["prerelease"] as? Bool == true {
            found = nil
            return nil
        }

        let latest = Self.normalize(tag)
        found = Self.isNewer(latest, than: Self.normalize(currentVersion))
            ? ReleaseInfo(version: latest, url: page)
            : nil
        return found
    }

    static func normalize(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }

    /// `.numeric` compares runs of digits by value, so 0.10.0 beats 0.9.0 —
    /// which plain lexicographic ordering gets backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard !candidate.isEmpty, !current.isEmpty else { return false }
        return candidate.compare(current, options: .numeric) == .orderedDescending
    }
}

public enum AppVersion {
    /// Reads the bundle rather than a constant, so it can't drift from what
    /// xcodebuild actually stamped in.
    public static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }
}
