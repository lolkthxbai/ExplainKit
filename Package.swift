// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMend",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SwiftMend", targets: ["SwiftMend"]),
        .library(name: "SwiftMendLiteRT", targets: ["SwiftMendLiteRT"]),
        .executable(name: "SwiftMendDemo", targets: ["SwiftMendDemo"])
    ],
    targets: [
        .binaryTarget(
            name: "CLiteRTLM",
            url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.16.0/CLiteRTLM.xcframework.zip",
            checksum: "4e0f683da07566ee79c143d2d58d387f77052b0e6a41562c969e5d2728fc9f4b"
        ),
        .binaryTarget(
            name: "CLiteRTLM_mac",
            url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.16.0/CLiteRTLM_mac.xcframework.zip",
            checksum: "3ae6c876abd74614b1869bfc40cb4d0b892981363564740268b1f8ac5cf895a4"
        ),
        .target(name: "SwiftMend"),
        .target(
            name: "SwiftMendLiteRT",
            dependencies: [
                "SwiftMend",
                .target(name: "CLiteRTLM", condition: .when(platforms: [.iOS])),
                .target(name: "CLiteRTLM_mac", condition: .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(name: "SwiftMendDemo", dependencies: ["SwiftMend"]),
        .testTarget(name: "SwiftMendTests", dependencies: ["SwiftMend", "SwiftMendDemo"]),
        .testTarget(
            name: "SwiftMendLiteRTTests",
            dependencies: ["SwiftMend", "SwiftMendLiteRT"]
        )
    ]
)
