// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanAssetsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanAssetsKit", targets: ["RichmanAssetsKit"])
    ],
    targets: [
        .target(name: "RichmanAssetsKit"),
        .testTarget(name: "RichmanAssetsKitTests", dependencies: ["RichmanAssetsKit"])
    ]
)
