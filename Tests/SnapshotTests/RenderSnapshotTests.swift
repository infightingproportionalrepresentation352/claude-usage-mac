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

    override func setUpWithError() throws {
        // Without an NSApplication, AppKit draws controls as unavailable — the
        // menu popover's buttons come out as prohibition badges. Touching
        // `shared` is enough to give them a real app context.
        _ = NSApplication.shared

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
            ("no-token", Snapshot(usage: nil, error: "no-token")),
            ("stale", Snapshot(usage: .init(
                fiveHour: UsageNode(utilization: 42, resetsAt: nil), sevenDay: nil),
                error: "network", stale: true)),
            ("no-data", nil),
        ]
    }

    private static func at(session: Double, weekly: Double) -> Snapshot {
        var stats = LogStats()
        stats.todayTokens = 1_240_000
        stats.todayCost = 3.40
        stats.weekTokens = 8_430_000
        stats.weekCost = 24.10
        stats.sessionTokens = 341_000
        stats.sessionCost = 1.02
        return Snapshot(
            usage: UsageData(
                fiveHour: UsageNode(utilization: session,
                                    resetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60)),
                sevenDay: UsageNode(utilization: weekly,
                                    resetsAt: Date().addingTimeInterval(4 * 86400 + 6 * 3600))),
            stats: stats)
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
        for scheme in [ColorScheme.light, .dark] {
            let view = SettingsView()
                .environment(\.colorScheme, scheme)
            try render(view, to: "settings-\(scheme.name).png")
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
