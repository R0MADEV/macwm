// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macwm",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacWMCore", targets: ["MacWMCore"]),
        .executable(name: "macwm-daemon", targets: ["MacWMDaemon"]),
        .executable(name: "macwm", targets: ["MacWMCLI"]),
        .executable(name: "macwm-bar", targets: ["MacWMBar"])
    ],
    targets: [
        .target(name: "MacWMCore"),
        .target(name: "MacWMTransport", dependencies: ["MacWMCore"]),
        .executableTarget(name: "MacWMDaemon", dependencies: ["MacWMCore", "MacWMTransport"]),
        .executableTarget(name: "MacWMCLI", dependencies: ["MacWMCore", "MacWMTransport"]),
        .executableTarget(name: "MacWMBar", dependencies: ["MacWMCore", "MacWMTransport"]),
        .testTarget(name: "MacWMCoreTests", dependencies: ["MacWMCore"])
    ]
)
