import XCTest
@testable import UsageCore

final class HistoryTests: XCTestCase {

    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func day(_ offset: Int, tokens: Int) -> DayUsage {
        let start = Calendar.current.startOfDay(for: Date())
        return DayUsage(day: Calendar.current.date(byAdding: .day, value: offset, to: start)!,
                        tokens: tokens, cost: Double(tokens) / 1e6)
    }

    func testPersistsAcrossInstances() {
        History(fileURL: file).merge([day(-1, tokens: 500), day(0, tokens: 900)])

        let reloaded = History(fileURL: file).recent(2)
        XCTAssertEqual(reloaded.map(\.tokens), [500, 900])
    }

    func testRescannedDaysOverwriteRatherThanAccumulate() {
        // The scan window is recomputed from scratch every poll, so merging the
        // same day twice must not double it.
        let history = History(fileURL: file)
        history.merge([day(0, tokens: 500)])
        history.merge([day(0, tokens: 800)])

        XCTAssertEqual(history.recent(1).map(\.tokens), [800])
    }

    func testDaysOutsideTheScanWindowSurvive() {
        // The whole reason history is persisted: Claude Code prunes transcripts,
        // and the scanner only reads the last 7 days.
        let history = History(fileURL: file)
        history.merge([day(-20, tokens: 4_000)])
        history.merge([day(0, tokens: 100)])

        let all = history.recent(21)
        XCTAssertEqual(all.first?.tokens, 4_000)
        XCTAssertEqual(all.last?.tokens, 100)
    }

    func testRecentFillsIdleDaysSoChartsStayAlignedToDates() {
        let history = History(fileURL: file)
        history.merge([day(-4, tokens: 700), day(0, tokens: 300)])

        let series = history.recent(5)
        XCTAssertEqual(series.count, 5)
        XCTAssertEqual(series.map(\.tokens), [700, 0, 0, 0, 300])
    }

    func testKeepsOnlyTheMostRecentDays() {
        let history = History(fileURL: file)
        history.merge((0..<(History.limit + 40)).map { day(-$0, tokens: 1) })

        // The oldest 40 are dropped, so they read back as gap-filled zeroes.
        let series = History(fileURL: file).recent(History.limit + 40)
        XCTAssertTrue(series.prefix(40).allSatisfy { $0.tokens == 0 })
        XCTAssertTrue(series.suffix(History.limit).allSatisfy { $0.tokens == 1 })
    }

    func testMissingAndCorruptFilesStartEmptyRatherThanCrashing() throws {
        try Data("not json".utf8).write(to: file)
        XCTAssertEqual(History(fileURL: file).recent(3).map(\.tokens), [0, 0, 0])
    }
}

final class UpdateCheckerTests: XCTestCase {

    func testStripsTagPrefix() {
        XCTAssertEqual(UpdateChecker.normalize("v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.normalize(" 1.2.3 "), "1.2.3")
    }

    func testComparesVersionsNumericallyNotLexicographically() {
        // The case plain string ordering gets backwards.
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.0", than: "0.10.0"))

        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "0.1.0"))
    }
}

final class ProjectNameTests: XCTestCase {

    func testTakesTheWorkingDirectoryLeaf() {
        XCTAssertEqual(
            TranscriptScanner.projectName("/Users/saeed/code/my-app"), "my-app")
        // Transcripts are written on Windows too.
        XCTAssertEqual(
            TranscriptScanner.projectName(#"C:\Users\Saeed\Documents\js_projects\my_app"#), "my_app")
        XCTAssertEqual(TranscriptScanner.projectName("/Users/saeed/code/"), "code")
    }

    func testMissingOrEmptyCwd() {
        XCTAssertNil(TranscriptScanner.projectName(nil))
        XCTAssertNil(TranscriptScanner.projectName(""))
        XCTAssertNil(TranscriptScanner.projectName(42))
    }
}
