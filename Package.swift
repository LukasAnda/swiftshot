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
    ]
)
