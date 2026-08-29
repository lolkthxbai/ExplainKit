// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMend",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SwiftMend", targets: ["SwiftMend"]),
        .library(name: "SwiftMendLiteRT", targets: ["SwiftMendLiteRT"]),
        .library(name: "SwiftMendEvaluation", targets: ["SwiftMendEvaluation"]),
        .executable(name: "SwiftMendBenchmark", targets: ["SwiftMendBenchmark"]),
        .executable(name: "SwiftMendDatasetTool", targets: ["SwiftMendDatasetTool"]),
        .executable(name: "SwiftMendCompare", targets: ["SwiftMendCompare"]),
        .executable(name: "SwiftMendModelTool", targets: ["SwiftMendModelTool"]),
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
        .target(
            name: "SwiftMendEvaluation",
            dependencies: ["SwiftMend"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "SwiftMendBenchmark",
            dependencies: ["SwiftMend", "SwiftMendEvaluation", "SwiftMendLiteRT"]
        ),
        .executableTarget(
            name: "SwiftMendDatasetTool",
            dependencies: ["SwiftMendEvaluation"]
        ),
        .executableTarget(
            name: "SwiftMendCompare",
            dependencies: ["SwiftMendEvaluation"]
        ),
        .executableTarget(
            name: "SwiftMendModelTool",
            dependencies: ["SwiftMendLiteRT"]
        ),
        .executableTarget(
            name: "SwiftMendDemo",
            dependencies: ["SwiftMend", "SwiftMendLiteRT"]
        ),
        .testTarget(
            name: "SwiftMendTests",
            dependencies: ["SwiftMend", "SwiftMendDemo", "SwiftMendLiteRT"]
        ),
        .testTarget(
            name: "SwiftMendLiteRTTests",
            dependencies: ["SwiftMend", "SwiftMendLiteRT"]
        ),
        .testTarget(
            name: "SwiftMendEvaluationTests",
            dependencies: ["SwiftMend", "SwiftMendEvaluation"]
        )
    ]
)
