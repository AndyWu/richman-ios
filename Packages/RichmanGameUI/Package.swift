// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanGameUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanGameUI", targets: ["RichmanGameUI"])
    ],
    targets: [
        .target(name: "RichmanGameUI"),
        .testTarget(name: "RichmanGameUITests", dependencies: ["RichmanGameUI"])
    ]
)
