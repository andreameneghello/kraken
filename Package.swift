// swift-tools-version: 5.9
import PackageDescription

/// Note: This package requires the GhosttyKit xcframework.
/// Build it first (see SETUP.md) and place it at Frameworks/GhosttyKit.xcframework.
let package = Package(
    name: "Kraken",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kraken",
            dependencies: ["GhosttyKit"],
            path: "Sources/Kraken",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Carbon"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
