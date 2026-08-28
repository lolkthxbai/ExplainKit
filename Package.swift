// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMend",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SwiftMend", targets: ["SwiftMend"]),
        .executable(name: "SwiftMendDemo", targets: ["SwiftMendDemo"])
    ],
    targets: [
        .target(name: "SwiftMend"),
        .executableTarget(name: "SwiftMendDemo", dependencies: ["SwiftMend"]),
        .testTarget(name: "SwiftMendTests", dependencies: ["SwiftMend", "SwiftMendDemo"])
    ]
)
