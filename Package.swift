// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Atoll",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Atoll", targets: ["Atoll"]),
    ],
    targets: [
        // Domain core: no AppKit/SwiftUI, fully testable with a fake HerdrClient.
        .target(name: "AtollCore"),
        .executableTarget(
            name: "Atoll",
            dependencies: ["AtollCore"],
            resources: [.copy("Resources/Sprites")]
        ),
        .testTarget(name: "AtollCoreTests", dependencies: ["AtollCore"]),
    ]
)
