// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExplainKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ExplainKit", targets: ["ExplainKit"]),
        .executable(name: "ExplainKitDemo", targets: ["ExplainKitDemo"])
    ],
    targets: [
        .target(name: "ExplainKit"),
        .executableTarget(name: "ExplainKitDemo", dependencies: ["ExplainKit"]),
        .testTarget(name: "ExplainKitTests", dependencies: ["ExplainKit", "ExplainKitDemo"])
    ]
)
