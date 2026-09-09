// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanGameUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanGameUI", targets: ["RichmanGameUI"])
    ],
    dependencies: [
        .package(path: "../RichmanCore"),
        .package(path: "../RichmanCityData"),
        .package(path: "../RichmanAssetsKit")
    ],
    targets: [
        .target(name: "RichmanGameUI", dependencies: ["RichmanCore", "RichmanCityData", "RichmanAssetsKit"]),
        .testTarget(name: "RichmanGameUITests", dependencies: ["RichmanGameUI"])
    ]
)
