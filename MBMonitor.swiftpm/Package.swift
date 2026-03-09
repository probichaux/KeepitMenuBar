// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MBMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MBMonitor", targets: ["MBMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "MBMonitor",
            dependencies: [],
            path: "Sources",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
