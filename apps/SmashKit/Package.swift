// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmashKit",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "SmashKit", targets: ["SmashKit"]),
    ],
    targets: [
        .target(name: "SmashKit"),
        .testTarget(
            name: "SmashKitTests",
            dependencies: ["SmashKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
