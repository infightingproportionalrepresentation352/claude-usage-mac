import Foundation

public struct Credentials: Sendable, Equatable {
    public let token: String?
    public let expired: Bool

    public static let none = Credentials(token: nil, expired: false)
}

/// Reads the OAuth access token Claude Code already stored on this machine.
/// We never authenticate ourselves and never write credentials anywhere.
public enum CredentialStore {

    public static var filePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json")
    }

    public static func read() -> Credentials {
        // macOS keeps the token in the login Keychain. Fall through to the file
        // anyway, since a machine can have both.
        if let fromKeychain = readKeychain(), fromKeychain.token != nil {
            return fromKeychain
        }
        return readFile() ?? .none
    }

    static func readFile() -> Credentials? {
        guard let data = try? Data(contentsOf: filePath) else { return nil }
        return parse(data)
    }

    static func readKeychain(timeout: TimeInterval = 60) -> Credentials? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
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
