// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Presence",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Presence", targets: ["Presence"]),
        .executable(name: "idle-probe", targets: ["idle-probe"]),
    ],
    targets: [
        .target(name: "PresenceCore"),
        .executableTarget(name: "Presence", dependencies: ["PresenceCore"]),
        .executableTarget(name: "idle-probe", dependencies: ["PresenceCore"]),
        .testTarget(name: "PresenceCoreTests", dependencies: ["PresenceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
