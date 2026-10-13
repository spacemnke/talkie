// swift-tools-version:5.9
import PackageDescription

var products: [Product] = []
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    // Switchboard rules, cord and mic physics. No AppKit, so it builds and tests on any platform.
    .target(name: "TalkieCore"),
    .testTarget(name: "TalkieCoreTests", dependencies: ["TalkieCore"])
]

#if os(macOS)
// The Mac app: menu bar item, switchboard window, floating mic.
// Supabase is the operator (accounts, codes, boards, knocks); LiveKit carries the voices;
// Sparkle keeps Talkie up to date.
products.append(.executable(name: "Talkie", targets: ["Talkie"]))
dependencies += [
    .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.3"),
    .package(url: "https://github.com/livekit/client-sdk-swift.git", exact: "2.17.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
]
targets.append(
    .executableTarget(
        name: "Talkie",
        dependencies: [
            "TalkieCore",
            .product(name: "Supabase", package: "supabase-swift"),
            .product(name: "LiveKit", package: "client-sdk-swift"),
            .product(name: "Sparkle", package: "Sparkle")
        ],
        resources: [.copy("Resources/Fonts")]
    )
)
#endif

let package = Package(
    name: "Talkie",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
