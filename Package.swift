// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayVDO",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DayVDO", targets: ["DayVDO"])
    ],
    targets: [
        .executableTarget(
            name: "DayVDO",
            path: "Sources/DayVDO",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DayVDOTests",
            dependencies: ["DayVDO"],
            path: "Tests/DayVDOTests"
        )
    ]
)
