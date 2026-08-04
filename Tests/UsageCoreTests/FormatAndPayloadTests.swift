import XCTest
@testable import UsageCore

final class FormatTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    func testUntil() {
        func until(_ seconds: TimeInterval) -> String {
            Format.until(now.addingTimeInterval(seconds), now: now)
        }
        XCTAssertEqual(until(4 * 86400 + 6 * 3600), "4d 6h")
        XCTAssertEqual(until(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(until(45 * 60), "45m")
        XCTAssertEqual(until(30), "0m")
        XCTAssertEqual(Format.until(nil), "")
    }

    func testUntilClampsInsteadOfCountingUpPastAReset() {
        XCTAssertEqual(Format.until(now.addingTimeInterval(-9999), now: now), "0m")
    }

    func testTokens() {
        XCTAssertEqual(Format.tokens(0), "0")
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertEqual(Format.tokens(1_000), "1.0K")
        XCTAssertEqual(Format.tokens(12_345), "12K")
        XCTAssertEqual(Format.tokens(1_200_000), "1.2M")
        XCTAssertEqual(Format.tokens(17_000_000), "17M")
        XCTAssertEqual(Format.tokens(1_200_000_000), "1.2B")
    }

    func testCost() {
        XCTAssertEqual(Format.cost(0), "$0.00")
        XCTAssertEqual(Format.cost(3.4), "$3.40")
        XCTAssertEqual(Format.cost(150), "$150")
        XCTAssertEqual(Format.cost(2_500), "$2.5k")
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(nil), "--")
        XCTAssertEqual(Format.percent(0), "0%")
        XCTAssertEqual(Format.percent(42.4), "42%")
        XCTAssertEqual(Format.percent(42.6), "43%")
    }

    func testLevelThresholds() {
        XCTAssertEqual(Level.of(nil), .none)
        XCTAssertEqual(Level.of(0), .ok)
        XCTAssertEqual(Level.of(49.9), .ok)
        XCTAssertEqual(Level.of(50), .warn)
        XCTAssertEqual(Level.of(79.9), .warn)
        XCTAssertEqual(Level.of(80), .critical)
        XCTAssertEqual(Level.of(100), .critical)
    }
}

final class UsagePayloadTests: XCTestCase {

    private func parse(_ json: String) -> UsageData? {
        UsageAPI.parse(Data(json.utf8))
    }

    func testParsesBothWindows() throws {
        let data = try XCTUnwrap(parse("""
        {"five_hour":{"utilization":42.5,"resets_at":"2026-08-04T18:00:00Z"},
         "seven_day":{"utilization":18,"resets_at":"2026-08-09T00:00:00.000Z"}}
        """))
        XCTAssertEqual(data.fiveHour?.utilization, 42.5)
        XCTAssertNotNil(data.fiveHour?.resetsAt)
        XCTAssertEqual(data.sevenDay?.utilization, 18)
        XCTAssertNotNil(data.sevenDay?.resetsAt)
    }

    func testToleratesUnknownFieldsAndMissingResetTimes() throws {
        // The endpoint is undocumented; a strict decoder would turn a new field
        // into a hard failure and blank the display.
        let data = try XCTUnwrap(parse("""
        {"five_hour":{"utilization":10,"resets_at":null,"something_new":{"a":1}},
         "opus_weekly":{"utilization":5},"account_uuid":"x"}
        """))
        XCTAssertEqual(data.fiveHour?.utilization, 10)
        XCTAssertNil(data.fiveHour?.resetsAt)
        XCTAssertNil(data.sevenDay)
    }

    func testRejectsBodiesWithNeitherWindow() {
        XCTAssertNil(parse("{}"))
        XCTAssertNil(parse(#"{"five_hour":null}"#))
        XCTAssertNil(parse(#"{"five_hour":{"resets_at":"2026-08-04T18:00:00Z"}}"#))
        XCTAssertNil(parse("not json"))
    }

    func testParsesBothIsoFlavours() {
        XCTAssertNotNil(parseDate("2026-08-04T18:00:00Z"))
        XCTAssertNotNil(parseDate("2026-08-04T18:00:00.945Z"))
        XCTAssertNil(parseDate(nil))
        XCTAssertNil(parseDate(""))
        XCTAssertNil(parseDate(12345))
    }
}

final class SnapshotTests: XCTestCase {

    func testSurvivesARoundTripThroughJson() throws {
        var stats = LogStats()
        stats.todayTokens = 123
        stats.todayCost = 4.56
        // Whole seconds on purpose: .iso8601 drops fractional seconds, which is
        // fine in practice (freshness is compared at second scale) but would
        // make an exact round-trip assertion flaky.
        let original = Snapshot(
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000),
            usage: UsageData(
                fiveHour: UsageNode(utilization: 42, resetsAt: Date(timeIntervalSince1970: 1_770_000_000)),
                sevenDay: UsageNode(utilization: 18, resetsAt: nil)),
            stats: stats,
            error: "http-429",
            stale: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(Snapshot.self, from: encoder.encode(original))
        XCTAssertEqual(restored, original)
    }

    func testEmptyUsageLeavesPercentagesNil() {
        let snapshot = Snapshot(usage: nil, error: "no-token")
        XCTAssertNil(snapshot.sessionPct)
        XCTAssertNil(snapshot.weeklyPct)
        XCTAssertEqual(snapshot.error, "no-token")
    }

    func testAlwaysHasSomewhereToWrite() {
        // App Groups may be unavailable, Application Support never is.
        XCTAssertFalse(Snapshot.locations.isEmpty)
    }
}
