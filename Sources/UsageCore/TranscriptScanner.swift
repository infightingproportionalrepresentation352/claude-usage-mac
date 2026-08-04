import Foundation

public struct LogStats: Codable, Sendable, Equatable {
    public var todayTokens: Int = 0
    public var todayCost: Double = 0
    public var weekTokens: Int = 0
    public var weekCost: Double = 0
    public var sessionTokens: Int = 0
    public var sessionCost: Double = 0
    /// False when ~/.claude/projects is missing or unreadable.
    public var ok: Bool = true

    public init() {}
}

struct LogEntry {
    let id: String
    let timestamp: Date?
    let tokens: Int
    let cost: Double
}

/// Walks ~/.claude/projects and totals token usage and cost.
///
/// Re-reading every recent transcript on each poll is fine for a one-shot CLI
/// and not fine for a process that polls every 60s — this machine has ~2.7 GB
/// of transcripts with a single 75 MB file in it. So each file's parsed entries
/// are cached and only bytes appended since the last read are parsed.
public actor TranscriptScanner {
    public static let shared = TranscriptScanner()

    private static let ttl: TimeInterval = 30
    private static let window: TimeInterval = 7 * 86400

    private struct FileState {
        var parsedOffset: UInt64 = 0
        var entries: [LogEntry] = []
    }

    private var files: [String: FileState] = [:]
    private var cached: LogStats?
    private var cachedAt: Date = .distantPast
    private let root: URL

    public init(projectsDirectory: URL? = nil) {
        self.root = projectsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
    }

    public func scan(force: Bool = false) -> LogStats {
        let now = Date()
        if !force, let cached, now.timeIntervalSince(cachedAt) < Self.ttl {
            return cached
        }

        var stats = LogStats()
        let found = listTranscripts()

        guard !found.isEmpty else {
            // Empty could mean "no logs yet" or "no such directory" — only the
            // latter is a problem worth surfacing.
            stats.ok = FileManager.default.fileExists(atPath: root.path)
            files.removeAll()
            cached = stats
            cachedAt = now
            return stats
        }

        // Newest-first; the most recently touched transcript is "the session".
        let sorted = found.sorted { $0.modified > $1.modified }
        let sessionPath = sorted[0].url.path
        let cutoff = now.addingTimeInterval(-Self.window)

        // Anything outside the window (and not the session file) is dropped from
        // the cache entirely, so memory tracks the window rather than growing.
        let live = sorted.filter { $0.modified >= cutoff || $0.url.path == sessionPath }
        let livePaths = Set(live.map(\.url.path))
        files = files.filter { livePaths.contains($0.key) }

        for file in live {
            refresh(file)
        }

        let calendar = Calendar.current
        var seenToday = Set<String>()
        var seenWeek = Set<String>()
        var seenSession = Set<String>()

        for file in live {
            guard let state = files[file.url.path] else { continue }
            let isSession = file.url.path == sessionPath

            for entry in state.entries {
                if isSession, claim(entry.id, in: &seenSession) {
                    stats.sessionTokens += entry.tokens
                    stats.sessionCost += entry.cost
                }
                guard let ts = entry.timestamp else { continue }
                if ts >= cutoff, claim(entry.id, in: &seenWeek) {
                    stats.weekTokens += entry.tokens
                    stats.weekCost += entry.cost
                }
                if calendar.isDateInToday(ts), claim(entry.id, in: &seenToday) {
                    stats.todayTokens += entry.tokens
                    stats.todayCost += entry.cost
                }
            }
        }

        cached = stats
        cachedAt = now
        return stats
    }

    /// Entries without an id can't be deduplicated, so they always count —
    /// double-counting a rare id-less entry beats dropping every one after the first.
    private func claim(_ id: String, in seen: inout Set<String>) -> Bool {
        id.isEmpty ? true : seen.insert(id).inserted
    }

    // MARK: - Incremental read

    private struct Transcript {
        let url: URL
        let modified: Date
        let size: UInt64
    }

    private func listTranscripts() -> [Transcript] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Transcript] = []
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            out.append(Transcript(url: url, modified: modified,
                                  size: UInt64(values.fileSize ?? 0)))
        }
        return out
    }

    private func refresh(_ file: Transcript) {
        var state = files[file.url.path] ?? FileState()

        // Truncated or rotated — the cached entries no longer describe this file.
        if file.size < state.parsedOffset {
            state = FileState()
        }
        guard file.size > state.parsedOffset else {
            files[file.url.path] = state
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.parsedOffset)
            guard let chunk = try handle.readToEnd(), !chunk.isEmpty else {
                files[file.url.path] = state
                return
            }
            state.parsedOffset += UInt64(Self.append(chunk, to: &state.entries))
        } catch {
            return  // leave the offset untouched; retry on the next poll
        }

        files[file.url.path] = state
    }

    /// Parses whole lines out of `chunk` and returns how many bytes were consumed.
    /// A trailing partial line is left unconsumed so the next read picks it up
    /// from the start — the offset only ever advances past a newline.
    static func append(_ chunk: Data, to entries: inout [LogEntry]) -> Int {
        guard let lastNewline = chunk.lastIndex(of: 0x0A) else { return 0 }
        let complete = chunk[chunk.startIndex...lastNewline]

        for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let entry = parseLine(Data(line)) { entries.append(entry) }
        }
        return chunk.distance(from: chunk.startIndex, to: lastNewline) + 1
    }

    /// Only assistant messages carry usage, and they are a minority of lines.
    /// A substring test costs a fraction of a full JSON parse, which matters when
    /// the cold-start read is hundreds of megabytes.
    /// ponytail: false positives (the word appearing in message text) just pay
    /// for a parse that then rejects them; only a false negative would lose data,
    /// and every usage-bearing line contains this by construction.
    private static let usageMarker = Data("\"usage\":".utf8)

    static func parseLine(_ line: Data) -> LogEntry? {
        guard line.range(of: usageMarker) != nil else { return nil }
        guard
            let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            obj["type"] as? String == "assistant",
            let message = obj["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        let model = message["model"] as? String ?? ""
        // Locally generated on API errors and interrupts — never billed.
        guard model != "<synthetic>" else { return nil }

        // Top-level fields are the totals; `usage.iterations` breaks the same
        // numbers down per iteration, so summing both would double-count.
        let tokens =
            intValue(usage["input_tokens"])
            + intValue(usage["output_tokens"])
            + intValue(usage["cache_creation_input_tokens"])
            + intValue(usage["cache_read_input_tokens"])

        return LogEntry(
            id: (obj["requestId"] as? String) ?? (message["id"] as? String) ?? "",
            timestamp: parseDate(obj["timestamp"]),
            tokens: tokens,
            cost: Pricing.cost(usage: usage, model: model))
    }
}
