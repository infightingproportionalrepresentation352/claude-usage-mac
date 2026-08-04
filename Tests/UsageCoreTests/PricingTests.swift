import XCTest
@testable import UsageCore

final class PricingTests: XCTestCase {

    func testFamilyCoversEveryModelIdSeenInRealTranscripts() {
        XCTAssertEqual(Pricing.family("claude-sonnet-5"), .sonnet)
        XCTAssertEqual(Pricing.family("claude-opus-4-8"), .opus)
        XCTAssertEqual(Pricing.family("claude-opus-4-7"), .opus)
        XCTAssertEqual(Pricing.family("claude-opus-5"), .opus)
        XCTAssertEqual(Pricing.family("claude-haiku-4-5-20251001"), .haiku)
        // Not an Anthropic pricing family we know — must not crash, falls to Sonnet rates.
        XCTAssertEqual(Pricing.family("claude-fable-5"), .unknown)
        XCTAssertEqual(Pricing.rate(for: "claude-fable-5"), Pricing.sonnet)
    }

    func testOnlyOpusFourZeroAndFourOneAreLegacyPriced() {
        XCTAssertEqual(Pricing.family("claude-opus-4-1"), .opusLegacy)
        XCTAssertEqual(Pricing.family("claude-opus-4-0"), .opusLegacy)
        XCTAssertEqual(Pricing.family("claude-3-opus-20240229"), .opusLegacy)
        XCTAssertEqual(Pricing.family("claude-opus-4-5"), .opus)
        XCTAssertEqual(Pricing.family("claude-opus-9"), .opus)
    }

    func testBareAliasIsCurrentPricingNotLegacy() {
        // Claude Code writes bare "opus"/"sonnet" aliases; those mean whatever is
        // current, so charging them the Opus-4 legacy rate would be 3x too much.
        XCTAssertEqual(Pricing.family("opus"), .opus)
        XCTAssertEqual(Pricing.family("sonnet"), .sonnet)
        XCTAssertEqual(Pricing.family("haiku"), .haiku)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(Pricing.family("CLAUDE-OPUS-5"), .opus)
    }

    // 1000 in, 2000 out, 10000 cache read, 1000 5m write, 3000 1h write
    private let usage: [String: Any] = [
        "input_tokens": 1000,
        "output_tokens": 2000,
        "cache_read_input_tokens": 10000,
        "cache_creation_input_tokens": 4000,
        "cache_creation": [
            "ephemeral_5m_input_tokens": 1000,
            "ephemeral_1h_input_tokens": 3000,
        ],
    ]

    func testSonnetCostUsesTheTtlSplit() {
        //  1000*3 + 2000*15 + 10000*0.3 + 1000*3.75 + 3000*6, per 1e6
        XCTAssertEqual(Pricing.cost(usage: usage, model: "claude-sonnet-5"),
                       0.05775, accuracy: 1e-12)
    }

    func testOpusCost() {
        //  1000*5 + 2000*25 + 10000*0.5 + 1000*6.25 + 3000*10, per 1e6
        XCTAssertEqual(Pricing.cost(usage: usage, model: "claude-opus-5"),
                       0.09625, accuracy: 1e-12)
    }

    func testOneHourCacheWritesCostMoreThanTheFlatFallback() {
        // The regression this port exists to fix: collapsing both TTLs into the
        // 5m rate (what the Stream Deck plugin does) understates real cost.
        var flat = usage
        flat.removeValue(forKey: "cache_creation")

        let split = Pricing.cost(usage: usage, model: "claude-sonnet-5")
        let collapsed = Pricing.cost(usage: flat, model: "claude-sonnet-5")

        XCTAssertEqual(collapsed, 0.051, accuracy: 1e-12)
        XCTAssertGreaterThan(split, collapsed)
    }

    func testFallsBackToFlatTotalWhenTtlBreakdownIsAbsent() {
        let legacy: [String: Any] = [
            "input_tokens": 1000,
            "cache_creation_input_tokens": 4000,
        ]
        //  (1000*3 + 4000*3.75) / 1e6
        XCTAssertEqual(Pricing.cost(usage: legacy, model: "claude-sonnet-5"),
                       0.018, accuracy: 1e-12)
    }

    func testMissingAndOddlyTypedFieldsCountAsZero() {
        XCTAssertEqual(Pricing.cost(usage: [:], model: "claude-sonnet-5"), 0, accuracy: 1e-12)
        // JSONSerialization hands back NSNumber; a double must not silently drop.
        let doubles: [String: Any] = ["input_tokens": 1000.0, "output_tokens": NSNumber(value: 2000)]
        //  (1000*3 + 2000*15) / 1e6
        XCTAssertEqual(Pricing.cost(usage: doubles, model: "claude-sonnet-5"),
                       0.033, accuracy: 1e-12)
    }
}
