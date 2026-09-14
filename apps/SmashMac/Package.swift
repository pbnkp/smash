// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmashMac",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../SmashKit")],
    targets: [
        .executableTarget(
            name: "SmashMac",
            dependencies: [.product(name: "SmashKit", package: "SmashKit")]
        )
    ]
)
