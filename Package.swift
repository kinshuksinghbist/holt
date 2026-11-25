// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Holt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Holt", targets: ["Holt"]),
        .executable(name: "holt-nm-host", targets: ["HoltNMHost"]),
        .library(name: "HoltCore", targets: ["HoltCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/rive-app/rive-ios.git", from: "6.24.0"),
    ],
    targets: [
        // All product logic. No SwiftUI imports here — keeps it fast to test.
        .target(
            name: "HoltCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.process("Resources")]
        ),
        // The macOS app: menu bar item, panel, main window.
        .executableTarget(
            name: "Holt",
            dependencies: [
                "HoltCore",
                .product(name: "RiveRuntime", package: "rive-ios"),
            ],
            resources: [.process("Resources")]
        ),
        // Native-messaging host launched by browsers; relays tab/YouTube events over Unix socket.
        .executableTarget(
            name: "HoltNMHost",
            dependencies: ["HoltCore"]
        ),
        .testTarget(
            name: "HoltCoreTests",
            dependencies: ["HoltCore"]
        ),
    ]
)
