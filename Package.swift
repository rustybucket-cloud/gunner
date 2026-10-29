// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gunner",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Gunner", path: "Sources/Gunner"),
        .testTarget(name: "GunnerTests", dependencies: ["Gunner"], path: "Tests/GunnerTests"),
    ]
)
