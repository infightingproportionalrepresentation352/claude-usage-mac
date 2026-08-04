import AppIntents
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    /// Non-nil when this widget is scoped to one project.
    let project: ProjectUsage?
    let scopeLabel: String?
    /// Set when the widget's configuration could not be honoured. Rendered
    /// instead of numbers, because showing some other account's figures under
    /// this widget's name is worse than showing nothing.
    var problem: WidgetProblem?

    init(date: Date, snapshot: Snapshot?, project: ProjectUsage?,
         scopeLabel: String?, problem: WidgetProblem? = nil) {
        self.date = date
        self.snapshot = snapshot
        self.project = project
        self.scopeLabel = scopeLabel
        self.problem = problem
    }
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
        let wantedProfile = configuration.profile?.id
        let wantedProject = configuration.project?.id

        guard let bundle = SnapshotBundle.read() else {
            // An older host writes only state.json. Honouring that for an
            // unconfigured widget is right; doing it for a configured one would
            // render the wrong account under the right label.
            guard wantedProfile == nil, wantedProject == nil else {
                return UsageEntry(date: Date(), snapshot: nil, project: nil,
                                  scopeLabel: nil, problem: .noData)
            }
            return UsageEntry(date: Date(), snapshot: Snapshot.read(),
                              project: nil, scopeLabel: nil)
        }

        let profile: Profile?
        let snapshot: Snapshot?
        if let wantedProfile {
            guard let match = bundle.snapshot(forExactly: wantedProfile) else {
                // Configured for an account this bundle doesn't have — the
                // folder moved, or was removed in Settings.
                return UsageEntry(date: Date(), snapshot: nil, project: nil,
                                  scopeLabel: bundle.profile(forExactly: wantedProfile)?.displayName
                                      ?? (wantedProfile as NSString).lastPathComponent,
                                  problem: .profileMissing)
            }
            profile = bundle.profile(forExactly: wantedProfile)
            snapshot = match
        } else {
            profile = bundle.defaultProfile
            snapshot = bundle.defaultSnapshot
        }

        let showsProfile = bundle.profileList.count > 1

        guard let wantedProject else {
            return UsageEntry(date: Date(), snapshot: snapshot, project: nil,
                              scopeLabel: showsProfile ? profile?.displayName : nil)
        }

        // A project with no activity this week is a real answer — zero — so
        // long as the account it belongs to did resolve.
        let project = snapshot?.stats.projects.first { $0.name == wantedProject }
            ?? ProjectUsage(name: wantedProject)
        let scope = showsProfile
            ? "\(profile?.displayName ?? "") · \(wantedProject)"
            : wantedProject
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
                        problem: entry.problem,
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
