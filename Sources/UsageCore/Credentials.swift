import CryptoKit
import Foundation

public struct Credentials: Sendable, Equatable {
    public let token: String?
    public let expired: Bool

    public static let none = Credentials(token: nil, expired: false)
}

/// Reads the OAuth access token Claude Code already stored on this machine.
/// We never authenticate ourselves and never write credentials anywhere.
public enum CredentialStore {

    static let keychainAccount = "claude-code-user"
    static let keychainBase = "Claude Code-credentials"

    /// File first, Keychain second.
    public static func read(for profile: Profile) -> Credentials {
        if let fromFile = readFile(at: profile.credentialsFile), fromFile.token != nil {
            return fromFile
        }
        for service in keychainServices(for: profile) {
            if let creds = readKeychain(service: service) { return creds }
        }
        return .none
    }

    /// Keychain service names to try for a profile, most likely first.
    ///
    /// Claude Code namespaces its Keychain item per config dir —
    /// `Claude Code-credentials-<sha256(dir)[0..<8]>`, account `claude-code-user` —
    /// and only the default dir gets the bare, unsuffixed name. The hash is taken
    /// over the raw `CLAUDE_CONFIG_DIR` string with no resolving, no symlink
    /// following and no trailing-slash trimming, so the exact spelling the user
    /// exported is what got hashed. We can't know that spelling, so we try the
    /// plausible ones; a miss costs one `security` exit and pops no dialog.
    ///
    /// This can't misattribute an account the way a bare fallback would: the hash
    /// *is* the per-profile key, so a profile that owns no item finds nothing.
    public static func keychainServices(for profile: Profile) -> [String] {
        let path = profile.configDir.path
        var spellings = [path, path + "/"]

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home + "/") {
            spellings.append("~" + String(path.dropFirst(home.count)))
        }

        // The default dir normally has the unsuffixed item — but a user who
        // exported CLAUDE_CONFIG_DIR pointing at ~/.claude anyway gets a hashed
        // one, so keep the hashed forms as fallbacks for it too.
        var services: [String] = profile.isDefault ? [keychainBase] : []
        services += spellings.map { "\(keychainBase)-\(sha8($0))" }
        return services
    }

    static func sha8(_ string: String) -> String {
        let nfc = Data(string.precomposedStringWithCanonicalMapping.utf8)
        return String(SHA256.hash(data: nfc)
            .map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    static func readFile(at url: URL) -> Credentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func readKeychain(service: String, timeout: TimeInterval = 60) -> Credentials? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        // ponytail: values over 2400B are stored chunked across accounts
        // `claude-code-user#0`, `#1`, … Pinning `-a` means we return nil on those
        // rather than parsing a base64 chunk as JSON. Reassemble if tokens ever
        // outgrow 2400B.
        task.arguments = ["find-generic-password", "-a", keychainAccount, "-w", "-s", service]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        guard (try? task.run()) != nil else { return nil }

        // The very first read pops a Keychain consent dialog and blocks until the
        // user answers, so the timeout is generous. It exists only so a wedged
        // `security` can't hold the poller forever.
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !task.isRunning else {
            task.terminate()
            return nil
        }
        // Safe to read after exit: the token is a few KB, well under the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Credentials? {
        // `security -w` appends a newline; JSONSerialization is happier without it.
        let trimmed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let bytes = trimmed.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }

        let token = oauth["accessToken"] as? String
        let expiresAtMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        let nowMs = Date().timeIntervalSince1970 * 1000
        return Credentials(token: token, expired: expiresAtMs > 0 && nowMs > expiresAtMs)
    }
}
