// swift-tools-version:5.9
import PackageDescription

// The app + widget bundle is built by Xcode (see project.yml). This package
// exists so the data layer can be built and tested with plain `swift test`,
// which is faster in CI and needs no project generation.
let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "usage-cli", targets: ["UsageCLI"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "UsageCLI", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
