import Foundation
import UsageCore

// Smoke test for the whole data path with no UI involved — CI runs this, and
// it's the fastest way to compare numbers against the Stream Deck plugin.
//
//   usage-cli            pretty summary
//   usage-cli --json     the snapshot as the widget will see it
//   usage-cli --write    also write it to disk (feeds a widget with no host app)

let args = Set(CommandLine.arguments.dropFirst())
let snapshot = await Refresh.snapshot(force: true)

if args.contains("--write") {
    let ok = snapshot.write()
    FileHandle.standardError.write(Data("write: \(ok ? "ok" : "failed")\n".utf8))
    for url in Snapshot.locations {
        FileHandle.standardError.write(Data("  \(url.path)\n".utf8))
    }
}

if args.contains("--json") {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(snapshot) {
        print(String(decoding: data, as: UTF8.self))
    }
} else {
    let s = snapshot
    if let error = s.error {
        print("error:   \(error)\(s.stale ? " (showing stale data)" : "")")
    }
    print("session: \(Format.percent(s.sessionPct))  resets \(Format.until(s.sessionResetsAt))")
    print("weekly:  \(Format.percent(s.weeklyPct))  resets \(Format.until(s.weeklyResetsAt))")
    print("today:   \(Format.tokens(s.stats.todayTokens))  \(Format.cost(s.stats.todayCost))")
    print("week:    \(Format.tokens(s.stats.weekTokens))  \(Format.cost(s.stats.weekCost))")
    print("session: \(Format.tokens(s.stats.sessionTokens))  \(Format.cost(s.stats.sessionCost))")
    if !s.stats.ok {
        print("note:    ~/.claude/projects not readable")
    }
}

// Non-zero on a failed fetch so CI can assert on it.
exit(snapshot.error == nil ? 0 : 1)
