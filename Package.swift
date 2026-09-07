// swift-tools-version: 6.3

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
    ],
    targets: [
        .target(
            name: "HueEntertainmentKit",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        ),
        .target(name: "HueEntertainmentEffects", dependencies: ["HueEntertainmentKit"]),
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
        ]),
        .testTarget(name: "HueEntertainmentEffectsTests", dependencies: ["HueEntertainmentEffects"]),
        .testTarget(name: "HueEntertainmentAudioTests", dependencies: ["HueEntertainmentAudio"]),
    ],
    swiftLanguageModes: [.v6]
)
