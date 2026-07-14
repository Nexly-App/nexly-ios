// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Nexly",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Nexly",
            targets: ["Nexly"]
        ),
    ],
    targets: [
        .target(
            name: "Nexly"
        ),
        .testTarget(
            name: "NexlyTests",
            dependencies: ["Nexly"]
        ),
    ]
)
