import Foundation

/// A resolved place: a display name plus a bounding box to scope the
/// subsequent Overpass query to.
struct GeocodedPlace: Equatable {
    let displayName: String
    let boundingBox: BoundingBox
}

struct BoundingBox: Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

/// Resolves a free-text city name to a bounding box using OpenStreetMap's
/// free Nominatim geocoder (https://nominatim.org/release-docs/latest/api/Search/).
/// No API key required, but usage policy asks for a descriptive User-Agent
/// and at most ~1 request/second — this app calls it once per new city and
/// caches the result (see `RichmanPersistence`), so that's easily respected.
struct NominatimGeocoder {
    private let session: URLSession
    private let userAgent = "RichmanApp/1.0 (https://github.com/AndyWu/richman-ios)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func geocode(cityName: String) async throws -> GeocodedPlace {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: cityName),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "addressdetails", value: "0")
        ]
        guard let url = components.url else {
            throw CityDataError.invalidResponse("Could not build Nominatim URL for \"\(cityName)\"")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw CityDataError.network(error.localizedDescription)
        }

        let results: [NominatimResult]
        do {
            results = try JSONDecoder().decode([NominatimResult].self, from: data)
        } catch {
            throw CityDataError.invalidResponse("Could not parse Nominatim response: \(error.localizedDescription)")
        }

        guard let first = results.first, let box = first.parsedBoundingBox else {
            throw CityDataError.cityNotFound(cityName)
        }
        return GeocodedPlace(displayName: first.display_name, boundingBox: box)
    }
}

private struct NominatimResult: Decodable {
    let display_name: String
    let boundingbox: [String]

    var parsedBoundingBox: BoundingBox? {
        guard boundingbox.count == 4,
              let minLat = Double(boundingbox[0]), let maxLat = Double(boundingbox[1]),
              let minLon = Double(boundingbox[2]), let maxLon = Double(boundingbox[3])
        else { return nil }
        return BoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
}
