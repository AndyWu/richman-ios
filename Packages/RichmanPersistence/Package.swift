// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanPersistence", targets: ["RichmanPersistence"])
    ],
    dependencies: [
        .package(path: "../RichmanCore"),
        .package(path: "../RichmanCityData")
    ],
    targets: [
        .target(name: "RichmanPersistence", dependencies: ["RichmanCore", "RichmanCityData"]),
        .testTarget(name: "RichmanPersistenceTests", dependencies: ["RichmanPersistence"])
    ]
)
