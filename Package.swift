// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ANTidy",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ANTidy", targets: ["ANTidy"])
    ],
    targets: [
        .executableTarget(
            name: "ANTidy",
            path: "Sources/ANTidy"
        )
    ]
)
