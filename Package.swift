// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "diff-engine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "DiffEngine",
            targets: ["DiffEngine"]
        ),
    ],
    targets: [
        .target(
            name: "DiffEngine",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DiffEngineTests",
            dependencies: ["DiffEngine"]
        ),
    ]
)
