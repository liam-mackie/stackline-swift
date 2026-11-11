// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stackline",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Stackline",
            path: "Sources",
            exclude: ["Stackline.entitlements", "Stackline-Release.entitlements"]
        ),
        .testTarget(
            name: "StacklineTests",
            dependencies: ["Stackline"],
            path: "StacklineTests"
        ),
    ]
)
