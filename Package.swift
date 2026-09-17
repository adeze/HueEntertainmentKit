// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HueEntertainmentKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "HueEntertainmentKit", targets: ["HueEntertainmentKit"]),
        .library(name: "HueEntertainmentEffects", targets: ["HueEntertainmentEffects"]),
        .library(name: "HueEntertainmentAudio", targets: ["HueEntertainmentAudio"]),
        .library(name: "HueEntertainmentTesting", targets: ["HueEntertainmentTesting"]),
        .executable(name: "hue-entertainment-diagnostics", targets: ["HueEntertainmentDiagnostics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.28.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.102.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.3"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.57.0"),
    ],
    targets: [
        .target(
            name: "HueEntertainmentKit",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "HueEntertainmentEffects",
            dependencies: [
                "HueEntertainmentKit",
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .target(name: "HueEntertainmentAudioRT"),
        .target(name: "HueEntertainmentAudio", dependencies: ["HueEntertainmentAudioRT"]),
        .target(name: "HueEntertainmentTesting", dependencies: [
            "HueEntertainmentKit",
            .product(name: "NIOCore", package: "swift-nio"),
        ]),
        .executableTarget(name: "HueEntertainmentDiagnostics", dependencies: ["HueEntertainmentKit"]),
        .testTarget(name: "HueEntertainmentKitTests", dependencies: [
            "HueEntertainmentKit",
            "HueEntertainmentTesting",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
        ]),
        .testTarget(name: "HueEntertainmentEffectsTests", dependencies: ["HueEntertainmentEffects"]),
        .testTarget(name: "HueEntertainmentAudioTests", dependencies: ["HueEntertainmentAudio"]),
    ],
    swiftLanguageModes: [.v6]
)
