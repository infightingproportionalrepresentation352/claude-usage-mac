import SwiftUI
import XCTest

/// Renders every view at every size, colour scheme, and data state to PNG.
///
/// This is the whole point of the target: the project is developed on Windows,
/// so CI uploading these images is the only way to actually look at the UI.
/// Assertions here are thin on purpose — a human (or a model) reads the output.
@MainActor
final class RenderSnapshotTests: XCTestCase {

    /// `<repo>/snapshots`, derived from this file's compile-time path rather than
    /// an environment variable — xcodebuild does not reliably forward the shell
    /// environment to the test runner, and CI needs to know where to look.
    private let outputDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/SnapshotTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("snapshots", isDirectory: true)

    // Known limitation: ImageRenderer draws interactive controls as unavailable,
    // so the menu popover's Refresh/Settings/Quit buttons come out as prohibition
    // badges. Instantiating NSApplication does not change it. Everything else in
    // these renders is faithful; the buttons need a real launch to review.

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        print("snapshots -> \(outputDirectory.path)")
    }

    // MARK: - States worth looking at

    private static var states: [(name: String, snapshot: Snapshot?)] {
        var busy = LogStats()
        busy.todayTokens = 12_400_000
        busy.todayCost = 148.20
        busy.weekTokens = 1_240_000_000
        busy.weekCost = 2_410.50
        busy.sessionTokens = 940_000
        busy.sessionCost = 12.05

        return [
            ("typical", .preview),
            ("warn", at(session: 64, weekly: 51)),
            ("critical", at(session: 97, weekly: 88)),
            ("fresh", at(session: 0, weekly: 3)),
            // Widest strings the layout has to survive without truncating.
            ("overflow", Snapshot(
                usage: UsageData(
                    fiveHour: UsageNode(utilization: 100,
                                        resetsAt: Date().addingTimeInterval(4 * 3600 + 59 * 60)),
                    sevenDay: UsageNode(utilization: 100,
                                        resetsAt: Date().addingTimeInterval(6 * 86400 + 23 * 3600))),
                stats: busy)),
            ("profile", {
                var scoped = Snapshot.preview
                scoped.profileLabel = "Work — saeed@acme.com"
                return scoped
            }()),
            ("no-token", Snapshot(usage: nil, error: "no-token")),
            ("stale", Snapshot(usage: .init(
                fiveHour: UsageNode(utilization: 42, resetsAt: nil), sevenDay: nil),
                error: "network", stale: true)),
            ("no-data", nil),
        ]
    }

    /// Only the percentages differ from the typical case — everything else stays
    /// populated so each state exercises the full layout.
    private static func at(session: Double, weekly: Double) -> Snapshot {
        var snapshot = Snapshot.preview
        snapshot.sessionPct = session
        snapshot.weeklyPct = weekly
        return snapshot
    }

    // MARK: - Tests

    func testRenderWidgetFaces() throws {
        for face in Face.allCases {
            for state in Self.states {
                for scheme in [ColorScheme.light, .dark] {
                    let view = UsageWidgetView(snapshot: state.snapshot, face: face)
                        .padding(face == .small ? 12 : 16)
                        .frame(width: face.size.width, height: face.size.height)
                        .background(scheme == .dark ? Color.black : Color.white)
                        .environment(\.colorScheme, scheme)

                    try render(view, to: "widget-\(face.rawValue)-\(state.name)-\(scheme.name).png")
                }
            }
        }
    }

    func testRenderMenuPopover() throws {
        for state in Self.states {
            for scheme in [ColorScheme.light, .dark] {
                let view = MenuView(snapshot: state.snapshot, isRefreshing: false)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)

                try render(view, to: "menu-\(state.name)-\(scheme.name).png")
            }
        }
    }

    func testRenderSettings() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cases: [(String, [Profile])] = [
            ("one", [Profile(configDir: home.appendingPathComponent(".claude"),
                             isDefault: true, email: "saeed@example.com",
                             organization: "Personal", plan: "Max")]),
            ("many", [
                Profile(configDir: home.appendingPathComponent(".claude"),
                        isDefault: true, email: "saeed@example.com",
                        organization: "Personal", plan: "Max"),
                Profile(configDir: home.appendingPathComponent(".claude-work"),
                        isDefault: false, email: "saeed@acme.com",
                        organization: "Acme Corp", plan: "Team"),
            ]),
            ("none", []),
        ]

        for (name, profiles) in cases {
            for scheme in [ColorScheme.light, .dark] {
                // Inert: no discovery against the real home, no poll loop.
                let view = SettingsView(poller: Poller(autostart: false, profiles: profiles))
                    .environment(\.colorScheme, scheme)
                try render(view, to: "settings-\(name)-\(scheme.name).png")
            }
        }
    }

    // MARK: - Rendering

    private func render<V: View>(_ view: V, to name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2  // Retina, so text is legible when reviewed

        let image = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced nothing for \(name)")
        XCTAssertGreaterThan(image.size.width, 0, "\(name) rendered with zero width")

        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        try png.write(to: outputDirectory.appendingPathComponent(name))
    }
}

private extension ColorScheme {
    var name: String { self == .dark ? "dark" : "light" }
}
