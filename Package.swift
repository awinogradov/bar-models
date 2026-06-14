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
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "BarModels", dependencies: ["UsageCore"], path: "App"),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
