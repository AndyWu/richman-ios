// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanCityData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanCityData", targets: ["RichmanCityData"])
    ],
    targets: [
        .target(name: "RichmanCityData"),
        .testTarget(name: "RichmanCityDataTests", dependencies: ["RichmanCityData"])
    ]
)
