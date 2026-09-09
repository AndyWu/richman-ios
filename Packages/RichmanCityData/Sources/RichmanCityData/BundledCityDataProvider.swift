import Foundation

/// Serves pre-baked `CityBoardLayout` JSON shipped in the app bundle — an
/// instant, offline demo path, and a fallback if a live Overpass/Nominatim
/// fetch fails. City files live in `Resources/BundledCities/<key>.json`,
/// generated with the `city-data-generator` tool in this package.
public struct BundledCityDataProvider: CityDataProvider {
    public static let availableCityKeys = ["new_york", "taipei"]

    private let bundle: Bundle
    private let fallback: CityDataProvider?

    public init(bundle: Bundle? = nil, fallback: CityDataProvider? = nil) {
        self.bundle = bundle ?? .module
        self.fallback = fallback
    }

    public func fetchBoardLayout(for cityName: String) async throws -> CityBoardLayout {
        if let layout = loadBundled(cityName) {
            return layout
        }
        if let fallback {
            return try await fallback.fetchBoardLayout(for: cityName)
        }
        throw CityDataError.cityNotFound(cityName)
    }

    private func loadBundled(_ cityName: String) -> CityBoardLayout? {
        let key = Self.normalize(cityName)
        guard let url = bundle.url(forResource: key, withExtension: "json", subdirectory: "BundledCities") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CityBoardLayout.self, from: data)
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}
