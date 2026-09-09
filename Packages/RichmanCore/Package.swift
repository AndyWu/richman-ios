// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanCore", targets: ["RichmanCore"])
    ],
    targets: [
        .target(name: "RichmanCore"),
        .testTarget(name: "RichmanCoreTests", dependencies: ["RichmanCore"])
    ]
)
