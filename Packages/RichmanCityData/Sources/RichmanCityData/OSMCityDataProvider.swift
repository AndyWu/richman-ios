import Foundation
import RichmanCore

/// The real `CityDataProvider`: geocodes a city with Nominatim, pulls its
/// streets/stations/landmarks from Overpass, and lays them out on a board.
/// See `Docs/CITY_DATA.md` for the full pipeline.
public struct OSMCityDataProvider: CityDataProvider {
    private let geocoder: NominatimGeocoder
    private let overpass: OverpassClient

    public init(session: URLSession = .shared) {
        self.geocoder = NominatimGeocoder(session: session)
        self.overpass = OverpassClient(session: session)
    }

    public func fetchBoardLayout(for cityName: String) async throws -> CityBoardLayout {
        let trimmed = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CityDataError.cityNotFound(cityName)
        }

        let place = try await geocoder.geocode(cityName: trimmed)
        let places = try await overpass.fetchPlaces(in: place.boundingBox)

        guard !places.isEmpty else {
            throw CityDataError.insufficientData(
                "No named streets, stations, or landmarks found for \"\(trimmed)\" — try a larger city or check spelling."
            )
        }

        let center = (
            lat: (place.boundingBox.minLat + place.boundingBox.maxLat) / 2,
            lon: (place.boundingBox.minLon + place.boundingBox.maxLon) / 2
        )
        let board = BoardLayoutBuilder.makeBoard(center: center, places: places)

        return CityBoardLayout(queriedName: trimmed, resolvedDisplayName: place.displayName, board: board)
    }
}
