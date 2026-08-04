import AppIntents
import WidgetKit

/// The Edit Widget form. Each placed widget carries its own scope, so you can
/// have one per account, or one per project, side by side.
///
/// Both parameters are plain `String`s rather than `AppEntity`s, deliberately.
/// An AppEntity is stored as an `EntityIdentifier`, which has to be mapped back
/// to a registered type when the extension resolves it — and when that lookup
/// fails it fails *silently*:
///
///     Failed to build EntityIdentifier. … is not a registered AppEntity identifier
///     Prepared profile to ProfileEntity(nil)
///
/// The parameter simply arrives nil and the widget renders the default account,
/// which looks exactly like the user's choice being ignored. A String is a
/// primitive: there is no type registry involved, so there is nothing to fail.
struct UsageConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Claude Usage"
    static var description = IntentDescription(
        "Choose which Claude account to show, and optionally a single project.")

    /// A profile's config directory path — the same value used as `Profile.id`.
    @Parameter(title: "Profile", optionsProvider: ProfileOptions())
    var profile: String?

    /// Nil means the whole account. A project has no limit percentages of its
    /// own — Anthropic reports those per account — so a project-scoped widget
    /// shows tokens, cost and history instead of gauges.
    @Parameter(title: "Project", optionsProvider: ProjectOptions())
    var project: String?
}

/// Runs inside the widget extension, which is sandboxed and cannot enumerate
/// config directories — so it reads the list the host already publishes.
struct ProfileOptions: DynamicOptionsProvider {
    /// Config directory paths, shown verbatim.
    ///
    /// A String parameter's picker renders the stored value itself —
    /// `ItemCollection` would give a separate label but requires the value type
    /// to be `DisplayRepresentable`, which String isn't. Abbreviating to `~/…`
    /// isn't an option either: inside the widget's sandbox, tilde expansion
    /// resolves to the container's home rather than the user's, so the two
    /// processes would disagree about the same folder. The full path is
    /// unambiguous, and it is exactly `Profile.id`, so no mapping is needed.
    func results() async throws -> [String] {
        (SnapshotBundle.read()?.profileList ?? []).map(\.id)
    }
}

struct ProjectOptions: DynamicOptionsProvider {
    /// Every project across every profile, busiest first. Not filtered by the
    /// chosen profile: AppIntents resolves parameters independently, and a name
    /// that doesn't exist in the selected account renders as zero.
    func results() async throws -> [String] {
        guard let bundle = SnapshotBundle.read() else { return [] }
        var seen = Set<String>()
        return bundle.profileList
            .compactMap { bundle.profiles[$0.id] }
            .flatMap(\.stats.projects)
            .sorted { $0.tokens > $1.tokens }
            .filter { seen.insert($0.name).inserted }
            .map(\.name)
    }
}
