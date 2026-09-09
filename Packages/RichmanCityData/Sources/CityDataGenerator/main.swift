import Foundation
import RichmanCityData

/// Dev tool: fetches a live `CityBoardLayout` for a city and writes it as
/// JSON, for use as a bundled offline-fallback city (see
/// `RichmanCityData/Resources/BundledCities` and `BundledCityDataProvider`).
///
/// Usage: swift run city-data-generator "New York" new_york.json

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("Usage: city-data-generator <city name> <output-file.json>")
    exit(1)
}
let cityName = arguments[1]
let outputPath = arguments[2]

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    do {
        let provider = OSMCityDataProvider()
        let layout = try await provider.fetchBoardLayout(for: cityName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(layout)
        try data.write(to: URL(fileURLWithPath: outputPath))
        print("Wrote \(outputPath) (\(layout.resolvedDisplayName))")
    } catch {
        print("Failed to generate city data for \"\(cityName)\": \(error)")
        exitCode = 1
    }
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)
