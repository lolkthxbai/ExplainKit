// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExplainKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ExplainKit", targets: ["ExplainKit"])
    ],
    targets: [
        .target(name: "ExplainKit"),
        .testTarget(name: "ExplainKitTests", dependencies: ["ExplainKit"])
    ]
)
