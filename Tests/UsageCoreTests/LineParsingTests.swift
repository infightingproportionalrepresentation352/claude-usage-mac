import XCTest
@testable import UsageCore

final class LineParsingTests: XCTestCase {

    private func line(_ s: String) -> Data { Data(s.utf8) }

    private let assistant = """
    {"type":"assistant","requestId":"req_1","timestamp":"2026-07-17T16:40:44.945Z",\
    "message":{"id":"msg_1","model":"claude-sonnet-5","usage":{"input_tokens":2,\
    "cache_creation_input_tokens":42936,"cache_read_input_tokens":28694,"output_tokens":1648,\
    "cache_creation":{"ephemeral_1h_input_tokens":42936,"ephemeral_5m_input_tokens":0}}}}
    """

    func testParsesARealAssistantEntry() throws {
        let entry = try XCTUnwrap(TranscriptScanner.parseLine(line(assistant)))
        XCTAssertEqual(entry.id, "req_1")
        XCTAssertEqual(entry.tokens, 2 + 1648 + 42936 + 28694)
        //  2*3 + 1648*15 + 28694*0.3 + 42936*6   (per 1e6, 1h cache write)
        let expected = (2 * 3 + 1648 * 15 + 28694 * 0.3 + 42936 * 6) / 1e6
        XCTAssertEqual(entry.cost, expected, accuracy: 1e-12)
        XCTAssertNotNil(entry.timestamp)
    }

    func testIgnoresEverythingThatIsNotAnAssistantMessageWithUsage() {
        XCTAssertNil(TranscriptScanner.parseLine(line(
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#)))
        XCTAssertNil(TranscriptScanner.parseLine(line(
            #"{"type":"summary","summary":"x"}"#)))
        XCTAssertNil(TranscriptScanner.parseLine(line(
            #"{"type":"assistant","message":{"model":"claude-sonnet-5"}}"#)))
        XCTAssertNil(TranscriptScanner.parseLine(line("not json at all")))
        XCTAssertNil(TranscriptScanner.parseLine(line("")))
    }

    func testSkipsSyntheticEntries() {
        // Generated locally on API errors and interrupts — never billed.
        let synthetic = assistant.replacingOccurrences(
            of: #""model":"claude-sonnet-5""#, with: #""model":"<synthetic>""#)
        XCTAssertNil(TranscriptScanner.parseLine(line(synthetic)))
    }

    func testFallsBackToMessageIdWhenRequestIdIsAbsent() throws {
        let noRequestId = assistant.replacingOccurrences(
            of: #""requestId":"req_1","#, with: "")
        let entry = try XCTUnwrap(TranscriptScanner.parseLine(line(noRequestId)))
        XCTAssertEqual(entry.id, "msg_1")
    }

    func testDoesNotDoubleCountTheIterationsBreakdown() throws {
        // `usage.iterations` repeats the same numbers per iteration; only the
        // top-level totals should be summed.
        let withIterations = assistant.replacingOccurrences(
            of: #""output_tokens":1648"#,
            with: #""output_tokens":1648,"iterations":[{"input_tokens":2,"output_tokens":1648}]"#)
        let entry = try XCTUnwrap(TranscriptScanner.parseLine(line(withIterations)))
        XCTAssertEqual(entry.tokens, 2 + 1648 + 42936 + 28694)
    }

    // MARK: - Incremental offset arithmetic

    func testConsumesOnlyWholeLines() {
        var entries: [LogEntry] = []
        let chunk = Data("\(assistant)\n{\"type\":\"assist".utf8)

        let consumed = TranscriptScanner.append(chunk, to: &entries)

        XCTAssertEqual(entries.count, 1)
        // Everything up to and including the newline; the partial line is left
        // for the next read to pick up from its start.
        XCTAssertEqual(consumed, assistant.utf8.count + 1)
        XCTAssertLessThan(consumed, chunk.count)
    }

    func testConsumesNothingWhenNoLineIsComplete() {
        var entries: [LogEntry] = []
        XCTAssertEqual(TranscriptScanner.append(Data("{\"partial\":".utf8), to: &entries), 0)
        XCTAssertEqual(TranscriptScanner.append(Data(), to: &entries), 0)
        XCTAssertTrue(entries.isEmpty)
    }

    func testResumingAtTheReturnedOffsetLosesNoEntries() {
        let full = Data("\(assistant)\n\(assistant)\n\(assistant)\n".utf8)

        // Cut mid-way through the second line, as a growing file would.
        let split = full.count - 40
        var entries: [LogEntry] = []
        let consumed = TranscriptScanner.append(full.prefix(split), to: &entries)
        _ = TranscriptScanner.append(full.suffix(from: consumed), to: &entries)

        XCTAssertEqual(entries.count, 3)
    }

    func testToleratesBlankLinesAndTrailingNewlines() {
        var entries: [LogEntry] = []
        let chunk = Data("\n\n\(assistant)\n\n".utf8)
        let consumed = TranscriptScanner.append(chunk, to: &entries)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(consumed, chunk.count)
    }
}
