import Foundation

/// Daily usage totals kept on disk.
///
/// The scanner only reads the last 7 days of transcripts, and Claude Code prunes
/// them after roughly a month — so anything longer than that has to be recorded
/// as it goes. Days inside the scan window are recomputed and overwrite what's
/// stored; older days keep whatever was last written.
///
/// Not thread-safe on purpose: every access goes through TranscriptScanner, which
/// is an actor, so the serialization is already there.
public final class History {

    /// Roughly a year. Small enough to rewrite whole on every scan (an Int and a
    /// Double per day), long enough that nobody notices the ceiling.
    public static let limit = 400

    private struct Store: Codable {
        var backfilled = false
        var days: [DayUsage] = []
    }

    private let url: URL
    private var store = Store()
    private var loaded = false

    public init(fileURL: URL? = nil) {
        self.url = fileURL ?? Self.defaultURL
    }

    public static var defaultURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// Folds freshly scanned days in and returns everything, oldest first.
    @discardableResult
    public func merge(_ scanned: [DayUsage]) -> [DayUsage] {
        load()
        var byDay = Dictionary(store.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        for day in scanned {
            byDay[day.day] = day
        }
        store.days = Array(byDay.values.sorted { $0.day < $1.day }.suffix(Self.limit))
        save()
        return store.days
    }

    /// The last `count` days including idle ones, so a chart's bars line up with
    /// dates instead of silently closing up over gaps.
    public func recent(_ count: Int, now: Date = Date()) -> [DayUsage] {
        load()
        let byDay = Dictionary(store.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDay[day] ?? DayUsage(day: day, tokens: 0, cost: 0)
        }
    }

    // MARK: - Backfill

    /// One-off pass over *every* transcript, not just the 7-day scan window, so a
    /// fresh install starts with the month of history Claude Code still holds
    /// rather than an empty chart that fills in over a week.
    ///
    /// Reads gigabytes. Callers run it once, off whatever path the UI waits on.
    /// The flag is persisted rather than inferred from the data, so a user who
    /// genuinely has only a few days of transcripts doesn't re-read everything
    /// on every launch.
    public func backfill(from root: URL) {
        load()
        guard !store.backfilled else { return }

        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return }

        let calendar = Calendar.current
        var seen = Set<String>()
        var totals: [Date: DayUsage] = [:]

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            // Mapped rather than read: some of these files are tens of megabytes
            // and we only touch each byte once.
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            var entries: [LogEntry] = []
            _ = TranscriptScanner.append(data, to: &entries)

            for entry in entries {
                guard let ts = entry.timestamp else { continue }
                if !entry.id.isEmpty, !seen.insert(entry.id).inserted { continue }
                let day = calendar.startOfDay(for: ts)
                totals[day, default: DayUsage(day: day, tokens: 0, cost: 0)].add(entry)
            }
        }

        // Anything already merged from a live scan wins — it used the same
        // arithmetic and is at least as fresh.
        let existing = Set(store.days.map(\.day))
        let merged = (store.days + totals.values.filter { !existing.contains($0.day) })
            .sorted { $0.day < $1.day }
        store.days = Array(merged.suffix(Self.limit))
        store.backfilled = true
        save()
    }

    // MARK: - Storage

    private func load() {
        guard !loaded else { return }
        loaded = true

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let stored = try? decoder.decode(Store.self, from: data) {
            store = stored
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(store) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
