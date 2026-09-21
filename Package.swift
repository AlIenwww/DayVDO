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
            resources: [.process("Resources")],
            // Xcode 27's Swift Build otherwise records the deployment target as
            // the linked SDK. Keep Xcode Run and the packaging script consistent.
            // This project is built with the macOS 27 SDK; deployment remains 15.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", "15.0",
                    "-Xlinker", "27.0"
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "DayVDOTests",
            dependencies: ["DayVDO"],
            path: "Tests/DayVDOTests"
        )
    ]
)
