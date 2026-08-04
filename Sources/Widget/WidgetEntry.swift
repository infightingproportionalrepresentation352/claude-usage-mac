import AppIntents
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    /// Non-nil when this widget is scoped to one project.
    let project: ProjectUsage?
    let scopeLabel: String?
}

struct UsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .preview, project: nil, scopeLabel: nil)
    }

    func snapshot(for configuration: UsageConfigIntent, in context: Context) async -> UsageEntry {
        // The widget gallery shows this, and it must look populated there even
        // when the host app has never run.
        context.isPreview ? placeholder(in: context) : entry(for: configuration)
    }

    func timeline(for configuration: UsageConfigIntent, in context: Context) async -> Timeline<UsageEntry> {
        // The host app pushes reloads as it polls, which is the real update path.
        // This is only the fallback for when it isn't running — and WidgetKit
        // budgets reloads anyway, so asking for anything tighter is wasted.
        Timeline(entries: [entry(for: configuration)],
                 policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: UsageConfigIntent) -> UsageEntry {
        guard let bundle = SnapshotBundle.read() else {
            // An older host writes only state.json; fall back rather than showing
            // an empty widget after a partial update.
            return UsageEntry(date: Date(), snapshot: Snapshot.read(),
                              project: nil, scopeLabel: nil)
        }

        let profileID = configuration.profile?.id
        let snapshot = bundle.snapshot(for: profileID)
        let profile = bundle.profile(for: profileID)

        guard let wanted = configuration.project?.id else {
            return UsageEntry(date: Date(), snapshot: snapshot, project: nil,
                              scopeLabel: bundle.profileList.count > 1 ? profile?.displayName : nil)
        }

        // A project selected under a different profile just has no rows here;
        // showing it as zero is truer than silently falling back to the account.
        let project = snapshot?.stats.projects.first { $0.name == wanted }
            ?? ProjectUsage(name: wanted)
        let scope = bundle.profileList.count > 1
            ? "\(profile?.displayName ?? "") · \(wanted)"
            : wanted
        return UsageEntry(date: Date(), snapshot: snapshot, project: project, scopeLabel: scope)
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(snapshot: entry.snapshot,
                        project: entry.project,
                        scopeLabel: entry.scopeLabel,
                        face: Face(family))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.saeedkolivand.claude-usage.widget",
                               intent: UsageConfigIntent.self,
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
