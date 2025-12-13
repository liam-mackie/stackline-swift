// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stackline",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Stackline",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources",
            exclude: ["Stackline.entitlements"]
        ),
        .testTarget(
            name: "StacklineTests",
            dependencies: ["Stackline"],
            path: "StacklineTests"
        ),
    ]
)
