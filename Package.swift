// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Holt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Holt", targets: ["Holt"]),
        .library(name: "HoltCore", targets: ["HoltCore"]),
    ],
    targets: [
        // All product logic. No SwiftUI imports here — keeps it fast to test.
        .target(name: "HoltCore"),
        // The macOS app: menu bar item, panel, main window.
        .executableTarget(
            name: "Holt",
            dependencies: ["HoltCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HoltCoreTests", dependencies: ["HoltCore"]),
    ]
)
