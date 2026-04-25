// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "diff-engine",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .watchOS(.v10),
    .tvOS(.v17),
    .visionOS(.v1),
  ],
  products: [
    .library(
      name: "DiffEngine",
      targets: ["DiffEngine"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/gnorium/embedded-swift-utilities", branch: "main")
  ],
  targets: [
    .target(
      name: "DiffEngine",
      dependencies: [
        .product(name: "EmbeddedSwiftUtilities", package: "embedded-swift-utilities")
      ],
      swiftSettings: [
        .enableExperimentalFeature("Embedded", .when(platforms: [.wasi])),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("StrictConcurrency"),
        .define("CLIENT", .when(platforms: [.wasi])),
        .define("SERVER", .when(platforms: [.macOS, .linux, .windows])),
      ]
    ),
    .testTarget(
      name: "DiffEngineTests",
      dependencies: ["DiffEngine"]
    ),
  ]
)
