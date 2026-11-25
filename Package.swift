// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Holt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Holt", targets: ["Holt"]),
        .library(name: "HoltCore", targets: ["HoltCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // All product logic. No SwiftUI imports here — keeps it fast to test.
        .target(
            name: "HoltCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // The macOS app: menu bar item, panel, main window.
        .executableTarget(
            name: "Holt",
            dependencies: ["HoltCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HoltCoreTests",
            dependencies: ["HoltCore"]
        ),
    ]
)
