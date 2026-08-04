import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        // The widget gallery shows this, and it must look populated there even
        // when the host app has never run.
        let snapshot = context.isPreview ? .preview : Snapshot.read()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: Snapshot.read())
        // The host app pushes reloads as it polls, which is the real update path.
        // This is only the fallback for when it isn't running — and WidgetKit
        // budgets reloads anyway, so asking for anything tighter is wasted.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(snapshot: entry.snapshot, face: Face(family))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.saeedkolivand.claude-usage.widget",
                            provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Session and weekly limits, tokens, and estimated cost.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

extension Face {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemLarge: self = .large
        default:           self = .medium
        }
    }
}
