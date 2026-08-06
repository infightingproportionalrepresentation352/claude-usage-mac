import CryptoKit
import Foundation

public struct ReleaseInfo: Codable, Sendable, Equatable {
    public var version: String
    public var url: URL
    /// The installable image and the checksum file published beside it. Both
    /// optional: a release with no assets is still worth announcing, it just
    /// can't be installed in place.
    public var dmg: URL?
    public var checksums: URL?
}

public enum Checksums {

    /// Reads one entry out of `shasum -a 256` output, which is
    /// `<64 hex chars><two spaces><filename>` per line.
    ///
    /// Splitting on whitespace means a filename containing a space would parse
    /// as its first word. The release assets are named by the workflow and
    /// never contain one, and a mismatch here fails closed — the install is
    /// refused rather than run unverified.
    public static func expected(for filename: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2, fields[1] == filename else { continue }
            return fields[0].lowercased()
        }
        return nil
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
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

        let assets = (root["assets"] as? [[String: Any]]) ?? []
        func asset(_ matches: (String) -> Bool) -> URL? {
            assets
                .first { ($0["name"] as? String).map(matches) ?? false }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }

        let latest = Self.normalize(tag)
        found = Self.isNewer(latest, than: Self.normalize(currentVersion))
            ? ReleaseInfo(version: latest,
                          url: page,
                          dmg: asset { $0.hasSuffix(".dmg") },
                          checksums: asset { $0 == "SHA256SUMS.txt" })
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

/// How this copy got installed, so the update instructions name the one command
/// that applies rather than offering both and leaving the user to work it out.
public enum InstallSource {
    /// The cask *moves* the app to /Applications, so `Bundle.main.bundleURL`
    /// looks identical either way. What it leaves behind is the Caskroom entry,
    /// and that is the only local evidence the install came from brew.
    ///
    /// Both prefixes are checked because the same user can have an Apple Silicon
    /// brew at /opt/homebrew and an Intel one under Rosetta at /usr/local.
    public static let caskroomPaths = [
        "/opt/homebrew/Caskroom/claude-usage",
        "/usr/local/Caskroom/claude-usage",
    ]

    /// Cheap enough to call from a view body: two `stat`s, no `brew` subprocess.
    /// A false negative just falls back to the DMG instructions, which still
    /// work, so this deliberately doesn't try harder than a path check.
    public static func isHomebrewCask(paths: [String] = caskroomPaths) -> Bool {
        paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
