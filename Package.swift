// swift-tools-version: 6.0
import PackageDescription

// UsageCore: the provider-agnostic parsing/aggregation/pricing/limits engine.
// Pure Swift, zero third-party dependencies, no UI imports — unit-testable via `swift test`.
// The macOS app target (SwiftUI MenuBarExtra) is a separate Xcode target that depends on this package.
let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "bar-models", targets: ["BarModels"]),
    ],
    dependencies: [
        // Sparkle is the in-app updater. It is a dependency of the SwiftUI app target
        // ONLY — UsageCore stays pure-Swift and third-party-free so it remains
        // unit-testable via `swift test` with no UI/framework linkage.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "BarModels",
            dependencies: ["UsageCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "App"
        ),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
