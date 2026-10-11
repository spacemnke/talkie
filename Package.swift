// swift-tools-version:5.9
import PackageDescription

var products: [Product] = []
var targets: [Target] = [
    // Switchboard rules, cord and mic physics. No AppKit, so it builds and tests on any platform.
    .target(name: "TalkieCore"),
    .testTarget(name: "TalkieCoreTests", dependencies: ["TalkieCore"])
]

#if os(macOS)
// The Mac app: menu bar item, switchboard window, floating mic.
products.append(.executable(name: "Talkie", targets: ["Talkie"]))
targets.append(
    .executableTarget(
        name: "Talkie",
        dependencies: ["TalkieCore"],
        resources: [.copy("Resources/Fonts")]
    )
)
#endif

let package = Package(
    name: "Talkie",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
