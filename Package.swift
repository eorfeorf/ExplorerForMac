// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExplorerForMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ExplorerForMac", targets: ["ExplorerForMac"])
    ],
    targets: [
        .executableTarget(
            name: "ExplorerForMac",
            path: ".",
            exclude: ["Tests", "docs", "ExplorerForMac.xcodeproj", "plan.md", "README.md"],
            sources: ["App", "Core", "Features", "Infrastructure"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ExplorerForMacTests",
            dependencies: ["ExplorerForMac"],
            path: "Tests/UnitTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
