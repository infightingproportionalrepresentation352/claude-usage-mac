import XCTest
@testable import UsageCore

final class ProfileDiscoveryTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeProfile(_ name: String, oauth: [String: Any]? = nil,
                             globalConfigName: String? = nil) throws -> URL {
        let dir = home.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("projects"), withIntermediateDirectories: true)
        if let oauth, let file = globalConfigName {
            try write(["oauthAccount": oauth], to: home.appendingPathComponent(file))
        }
        return dir
    }

    private func write(_ json: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    private func discover(env: [String: String] = [:], extra: [String] = []) -> [Profile] {
        ProfileStore.discover(extraPaths: extra, environment: env, home: home)
    }

    // MARK: - What counts as a profile

    func testADirectoryWithTranscriptsIsAProfile() throws {
        try makeProfile(".claude")
        let profiles = discover()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles[0].isDefault)
    }

    func testCredentialsAreNotRequired() throws {
        // They can be relocated, or live in the Keychain / Credential Manager
        // with no file at all — requiring one would hide real profiles.
        try makeProfile(".claude")
        XCTAssertEqual(discover().count, 1)
    }

    func testDirectoriesWithoutTranscriptsAreIgnored() throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude-flow"), withIntermediateDirectories: true)
        try makeProfile(".claude")
        XCTAssertEqual(discover().map(\.configDir.lastPathComponent), [".claude"])
    }

    func testFindsRelocatedSiblings() throws {
        try makeProfile(".claude")
        try makeProfile(".claude-work")
        XCTAssertEqual(discover().map(\.configDir.lastPathComponent).sorted(),
                       [".claude", ".claude-work"])
    }

    func testDefaultComesFirst() throws {
        try makeProfile(".claude-aaa")
        try makeProfile(".claude")
        XCTAssertTrue(discover().first?.isDefault == true)
    }

    func testOnlyTheDefaultDirectoryIsMarkedDefault() throws {
        try makeProfile(".claude")
        try makeProfile(".claude-work")
        let work = try XCTUnwrap(discover().first { $0.configDir.lastPathComponent == ".claude-work" })
        XCTAssertFalse(work.isDefault)
    }

    func testHonoursClaudeConfigDir() throws {
        let relocated = home.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(
            at: relocated.appendingPathComponent("projects"), withIntermediateDirectories: true)

        let profiles = discover(env: ["CLAUDE_CONFIG_DIR": relocated.path])
        XCTAssertEqual(profiles.map(\.configDir.lastPathComponent), ["elsewhere"])
        XCTAssertFalse(profiles[0].isDefault, "a relocated dir is not the default")
    }

    func testNoDuplicatesWhenSourcesOverlap() throws {
        let dir = try makeProfile(".claude")
        let profiles = discover(env: ["CLAUDE_CONFIG_DIR": dir.path], extra: [dir.path])
        XCTAssertEqual(profiles.count, 1)
    }

    func testExtraPathsAreIncluded() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outside.appendingPathComponent("projects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        XCTAssertEqual(discover(extra: [outside.path]).count, 1)
    }

    func testNothingFoundIsEmptyNotACrash() {
        XCTAssertTrue(discover().isEmpty)
    }

    // MARK: - Where identity comes from

    func testDefaultProfileReadsItsSiblingGlobalConfig() throws {
        // ~/.claude.json sits NEXT TO ~/.claude, not inside it.
        try makeProfile(".claude",
                        oauth: ["emailAddress": "me@example.com",
                                "organizationName": "Acme",
                                "organizationRateLimitTier": "default_claude_max_20x"],
                        globalConfigName: ".claude.json")

        let profile = try XCTUnwrap(discover().first)
        XCTAssertEqual(profile.email, "me@example.com")
        XCTAssertEqual(profile.organization, "Acme")
        XCTAssertEqual(profile.plan, "Max")
    }

    func testRelocatedProfileReadsTheConfigInsideItself() throws {
        let dir = try makeProfile(".claude-work")
        try write(["oauthAccount": ["emailAddress": "work@example.com"]],
                  to: dir.appendingPathComponent(".claude.json"))

        let profile = try XCTUnwrap(discover().first)
        XCTAssertEqual(profile.email, "work@example.com")
    }

    func testRelocatedProfileNeverInheritsTheDefaultAccountsIdentity() throws {
        // ~/.claude-work's parent is also ~, so an ungated sibling lookup would
        // stamp the default account's email onto every relocated profile.
        try makeProfile(".claude",
                        oauth: ["emailAddress": "personal@example.com"],
                        globalConfigName: ".claude.json")
        try makeProfile(".claude-work")

        let work = try XCTUnwrap(discover().first { !$0.isDefault })
        XCTAssertNil(work.email, "picked up the default profile's identity")
    }

    func testConfigJsonWinsOverClaudeJson() throws {
        let dir = try makeProfile(".claude-work")
        try write(["oauthAccount": ["emailAddress": "old@example.com"]],
                  to: dir.appendingPathComponent(".claude.json"))
        try write(["oauthAccount": ["emailAddress": "new@example.com"]],
                  to: dir.appendingPathComponent(".config.json"))

        XCTAssertEqual(discover().first?.email, "new@example.com")
    }

    func testMissingOrCorruptGlobalConfigStillYieldsAUsableProfile() throws {
        let dir = try makeProfile(".claude-work")
        try Data("not json".utf8).write(to: dir.appendingPathComponent(".claude.json"))

        let profile = try XCTUnwrap(discover().first)
        XCTAssertNil(profile.email)
        XCTAssertEqual(profile.displayName, ".claude-work")
    }

    func testPlanLabel() {
        XCTAssertEqual(ProfileStore.planLabel("default_claude_max_20x"), "Max")
        XCTAssertEqual(ProfileStore.planLabel("claude_pro"), "Pro")
        XCTAssertEqual(ProfileStore.planLabel("enterprise_thing"), "Enterprise")
        XCTAssertNil(ProfileStore.planLabel("something_unknown"))
        XCTAssertNil(ProfileStore.planLabel(nil))
    }

    func testDisplayName() throws {
        try makeProfile(".claude", oauth: ["emailAddress": "me@example.com"],
                        globalConfigName: ".claude.json")
        XCTAssertEqual(discover().first?.displayName, "Default — me@example.com")
    }
}

final class ProfileCredentialsTests: XCTestCase {

    private func profile(_ dir: URL, isDefault: Bool) -> Profile {
        Profile(configDir: dir, isDefault: isDefault)
    }

    func testReadsTheProfilesOwnCredentialsFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("creds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let future = (Date().timeIntervalSince1970 + 3600) * 1000
        try JSONSerialization
            .data(withJSONObject: ["claudeAiOauth": ["accessToken": "tok", "expiresAt": future]])
            .write(to: dir.appendingPathComponent(".credentials.json"))

        let creds = CredentialStore.read(for: profile(dir, isDefault: false))
        XCTAssertEqual(creds.token, "tok")
        XCTAssertFalse(creds.expired)
    }

    func testNonDefaultProfileNeverFallsBackToTheKeychain() {
        // There is one Keychain item with a fixed service name and no per-profile
        // variant. Falling back would show another account's percentages under
        // this profile's name — wrong, and invisibly so.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)", isDirectory: true)

        XCTAssertNil(CredentialStore.read(for: profile(missing, isDefault: false)).token)
    }
}

final class ProfileHistoryTests: XCTestCase {

    func testDefaultProfileKeepsTheOriginalFilename() {
        // The file shipped in v0.2.0 must not need migrating.
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        let url = History.url(for: Profile(configDir: dir, isDefault: true))
        XCTAssertEqual(url.lastPathComponent, "history.json")
    }

    func testOtherProfilesGetTheirOwnFile() {
        let a = History.url(for: Profile(configDir: URL(fileURLWithPath: "/Users/x/.claude-work"),
                                         isDefault: false))
        let b = History.url(for: Profile(configDir: URL(fileURLWithPath: "/Users/x/.claude-side"),
                                         isDefault: false))
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.lastPathComponent.hasPrefix("history-"))
    }

    func testTwoProfilesDoNotClobberEachOther() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let today = Calendar.current.startOfDay(for: Date())
        let a = History(fileURL: root.appendingPathComponent("a.json"))
        let b = History(fileURL: root.appendingPathComponent("b.json"))

        a.merge([DayUsage(day: today, tokens: 100, cost: 1)])
        b.merge([DayUsage(day: today, tokens: 900, cost: 9)])

        XCTAssertEqual(a.recent(1).first?.tokens, 100)
        XCTAssertEqual(b.recent(1).first?.tokens, 900)
    }

    func testSlugIsReadable() {
        XCTAssertEqual(History.slug("/Users/saeed/.claude-work"), "users-saeed-claude-work")
    }
}
