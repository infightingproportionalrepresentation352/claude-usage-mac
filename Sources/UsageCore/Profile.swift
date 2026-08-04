import Foundation

/// One Claude Code config directory, i.e. one logged-in account.
///
/// `CLAUDE_CONFIG_DIR` relocates the whole `~/.claude` tree, and that is the only
/// profile mechanism Claude Code has — there is no in-app switcher, and `/login`
/// overwrites whatever account a directory currently holds.
public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public var configDir: URL
    public var isDefault: Bool
    /// From the global config's `oauthAccount`. Absent is normal and fine — a
    /// directory with transcripts but no global config is still usable.
    public var email: String?
    public var organization: String?
    public var plan: String?

    public var id: String { configDir.path }

    public init(configDir: URL, isDefault: Bool,
                email: String? = nil, organization: String? = nil, plan: String? = nil) {
        self.configDir = configDir
        self.isDefault = isDefault
        self.email = email
        self.organization = organization
        self.plan = plan
    }

    public var projectsDirectory: URL {
        configDir.appendingPathComponent("projects", isDirectory: true)
    }

    public var credentialsFile: URL {
        configDir.appendingPathComponent(".credentials.json")
    }

    public var displayName: String {
        let base = isDefault ? "Default" : configDir.lastPathComponent
        guard let email, !email.isEmpty else { return base }
        return "\(base) — \(email)"
    }
}

public enum ProfileStore {

    public static let extraPathsKey = "extraProfilePaths"

    /// Folders the user pointed at by hand, for config dirs that live somewhere
    /// discovery would never look.
    public static func savedExtraPaths(
        defaults: UserDefaults = .standard
    ) -> [String] {
        defaults.stringArray(forKey: extraPathsKey) ?? []
    }

    public static func addExtraPath(_ path: String, defaults: UserDefaults = .standard) {
        var paths = savedExtraPaths(defaults: defaults)
        guard !paths.contains(path) else { return }
        paths.append(path)
        defaults.set(paths, forKey: extraPathsKey)
    }

    public static func removeExtraPath(_ path: String, defaults: UserDefaults = .standard) {
        defaults.set(savedExtraPaths(defaults: defaults).filter { $0 != path },
                     forKey: extraPathsKey)
    }

    /// Every profile on this machine, default first.
    ///
    /// `environment` and `home` are injectable so the tests can build a fake
    /// filesystem instead of depending on whoever runs them.
    public static func discover(
        extraPaths: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL? = nil
    ) -> [Profile] {
        let home = home ?? FileManager.default.homeDirectoryForCurrentUser
        let defaultDir = home.appendingPathComponent(".claude", isDirectory: true)

        var candidates: [URL] = []

        // Rarely fires: a menu bar app launched from Finder or as a login item
        // inherits no shell environment. Free and correct when it does.
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath:
                (configured as NSString).expandingTildeInPath, isDirectory: true))
        }
        candidates.append(defaultDir)
        candidates.append(contentsOf: siblings(of: home))
        candidates.append(contentsOf: extraPaths.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        })

        var seen = Set<String>()
        var profiles: [Profile] = []
        for candidate in candidates {
            let dir = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(dir.path).inserted, isProfile(dir) else { continue }
            profiles.append(profile(at: dir, isDefault: dir.path == defaultDir
                .resolvingSymlinksInPath().standardizedFileURL.path))
        }
        return profiles
    }

    /// Transcripts are the only thing that makes a directory worth reading.
    /// Deliberately not requiring `.credentials.json` — it can be moved by
    /// `CLAUDE_SECURESTORAGE_CONFIG_DIR` or `CLAUDE_CODE_HOST_CREDS_FILE`, or live
    /// in the Keychain or Windows Credential Manager with no file at all.
    static func isProfile(_ dir: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let projects = dir.appendingPathComponent("projects", isDirectory: true)
        return FileManager.default.fileExists(atPath: projects.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func siblings(of home: URL) -> [URL] {
        // No .skipsHiddenFiles: every candidate here starts with a dot.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return [] }

        return entries
            .filter { $0.lastPathComponent.hasPrefix(".claude") }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func profile(at dir: URL, isDefault: Bool) -> Profile {
        var profile = Profile(configDir: dir, isDefault: isDefault)
        guard let config = globalConfigURL(for: dir, isDefault: isDefault),
              let data = try? Data(contentsOf: config),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any]
        else { return profile }

        profile.email = account["emailAddress"] as? String
        profile.organization = account["organizationName"] as? String
        profile.plan = planLabel(account["organizationRateLimitTier"] as? String)
        return profile
    }

    /// Where the account identity lives, which depends on the profile.
    ///
    /// A relocated profile keeps its global config *inside* the config dir; the
    /// default profile keeps it as a *sibling* — `~/.claude.json`, not
    /// `~/.claude/.claude.json`. The sibling branch is gated to the default
    /// profile on purpose: `~/.claude-work`'s parent is also `~`, so applying it
    /// everywhere would stamp the default account's email onto every relocated
    /// profile.
    static func globalConfigURL(for dir: URL, isDefault: Bool) -> URL? {
        var candidates = [
            dir.appendingPathComponent(".config.json"),
            dir.appendingPathComponent(".claude.json"),
        ]
        if isDefault {
            candidates.append(dir.deletingLastPathComponent().appendingPathComponent(".claude.json"))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// "default_claude_max_20x" -> "Max". Anything unrecognised stays nil rather
    /// than putting a raw internal tier string in front of the user.
    static func planLabel(_ tier: String?) -> String? {
        guard let tier = tier?.lowercased() else { return nil }
        for name in ["enterprise", "team", "max", "pro", "free"] where tier.contains(name) {
            return name.capitalized
        }
        return nil
    }
}
