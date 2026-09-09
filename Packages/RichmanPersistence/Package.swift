// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanPersistence", targets: ["RichmanPersistence"])
    ],
    targets: [
        .target(name: "RichmanPersistence"),
        .testTarget(name: "RichmanPersistenceTests", dependencies: ["RichmanPersistence"])
    ]
)
