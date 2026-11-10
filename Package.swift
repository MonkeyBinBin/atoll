// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrIsland",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "HerdrIsland", targets: ["HerdrIsland"]),
    ],
    targets: [
        // Domain core: no AppKit/SwiftUI, fully testable with a fake HerdrClient.
        .target(name: "IslandCore"),
        .executableTarget(
            name: "HerdrIsland",
            dependencies: ["IslandCore"],
            resources: [.copy("Resources/Sprites")]
        ),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
