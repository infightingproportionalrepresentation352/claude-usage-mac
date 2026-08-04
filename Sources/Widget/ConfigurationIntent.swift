import AppIntents
import WidgetKit

/// The Edit Widget form. Each placed widget carries its own scope, so you can
/// have one per account, or one per project, side by side.
struct UsageConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Claude Usage"
    static var description = IntentDescription(
        "Choose which Claude account to show, and optionally a single project.")

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    /// Nil means the whole account. A project has no limit percentages of its
    /// own — Anthropic reports those per account — so a project-scoped widget
    /// shows tokens, cost and history instead of gauges.
    @Parameter(title: "Project")
    var project: ProjectEntity?
}

// MARK: - Profile

struct ProfileEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    static var defaultQuery = ProfileQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Runs inside the widget extension, which is sandboxed and cannot enumerate
/// config directories — so it reads the list the host already publishes.
struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        let all = try await suggestedEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        (SnapshotBundle.read()?.profileList ?? []).map {
            ProfileEntity(id: $0.id, name: $0.displayName)
        }
    }

    func defaultResult() async -> ProfileEntity? {
        try? await suggestedEntities().first
    }
}

// MARK: - Project

struct ProjectEntity: AppEntity {
    /// The project name doubles as the id — it's what transcripts attribute by,
    /// and it is what a person recognises in the picker.
    var id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = ProjectQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct ProjectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        identifiers.map { ProjectEntity(id: $0) }
    }

    /// Every project across every profile, busiest first. Not filtered by the
    /// chosen profile: AppIntents resolves parameters independently, and a name
    /// that doesn't exist in the selected profile simply renders as zero.
    func suggestedEntities() async throws -> [ProjectEntity] {
        guard let bundle = SnapshotBundle.read() else { return [] }
        var seen = Set<String>()
        return bundle.profileList
            .compactMap { bundle.profiles[$0.id] }
            .flatMap(\.stats.projects)
            .sorted { $0.tokens > $1.tokens }
            .filter { seen.insert($0.name).inserted }
            .map { ProjectEntity(id: $0.name) }
    }
}
