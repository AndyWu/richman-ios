// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RichmanCityData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RichmanCityData", targets: ["RichmanCityData"]),
        .executable(name: "city-data-generator", targets: ["CityDataGenerator"])
    ],
    dependencies: [
        .package(path: "../RichmanCore")
    ],
    targets: [
        .target(
            name: "RichmanCityData",
            dependencies: ["RichmanCore"],
            resources: [.copy("Resources/BundledCities")]
        ),
        .executableTarget(name: "CityDataGenerator", dependencies: ["RichmanCityData"]),
        .testTarget(name: "RichmanCityDataTests", dependencies: ["RichmanCityData"])
    ]
)
