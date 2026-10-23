// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "swiftshot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "swiftshot",
            path: "Sources/swiftshot",
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-availability-checking"])]
        ),
        // Fast, no simulator: options, device data, display table.
        .testTarget(name: "swiftshotTests", dependencies: ["swiftshot"], path: "Tests/swiftshotTests"),
        // End to end on Example/DemoApp (needs Xcode, an iOS runtime and `make`): no-boot output
        // against a booted simulator's framebuffer, and performance budgets.
        // SWIFTSHOT_INTEGRATION=1 swift test --filter IntegrationTests
        .testTarget(name: "IntegrationTests", path: "Tests/IntegrationTests"),
    ]
)
