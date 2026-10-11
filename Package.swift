// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Talkie",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Talkie", targets: ["Talkie"])
    ],
    targets: [
        // Switchboard rules, cord and mic physics. No AppKit, so it's quick to test.
        .target(name: "TalkieCore"),
        // The Mac app: menu bar item, switchboard window, floating mic.
        .executableTarget(
            name: "Talkie",
            dependencies: ["TalkieCore"],
            resources: [.copy("Resources/Fonts")]
        ),
        .testTarget(name: "TalkieCoreTests", dependencies: ["TalkieCore"])
    ]
)
