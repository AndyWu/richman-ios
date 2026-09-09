import Foundation

/// A single point of interest pulled from OpenStreetMap: a named road,
/// station, or landmark, with enough info to rank and place it on the board.
struct OverpassPlace: Equatable {
    enum Kind: Equatable {
        case road(highwayClass: String)
        case station
        case landmark
    }

    let name: String
    let kind: Kind
    let latitude: Double
    let longitude: Double
}

/// Queries the free, keyless Overpass API (https://overpass-api.de) for named
/// roads, train/subway stations, and notable landmarks within a bounding box.
struct OverpassClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPlaces(in box: BoundingBox) async throws -> [OverpassPlace] {
        let query = Self.buildQuery(for: box)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).map { Data($0.utf8) }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw CityDataError.network(error.localizedDescription)
        }

        let response: OverpassResponse
        do {
            response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        } catch {
            throw CityDataError.invalidResponse("Could not parse Overpass response: \(error.localizedDescription)")
        }

        return response.elements.compactMap { $0.toPlace() }
    }

    /// Named major roads, railway/subway stations, and a handful of landmark
    /// types, all scoped to the bounding box. `out center` gives ways (roads,
    /// aerodromes) a single representative coordinate instead of full
    /// geometry. Each block has its own numeric `out` cap — a city the size
    /// of New York has 50,000+ named road segments (OSM splits roads at
    /// every intersection), and we only need a few dozen distinct names, so
    /// uncapped queries return tens of megabytes for no benefit. Capping
    /// keeps this a good citizen of the free, shared Overpass instance and
    /// keeps the fetch fast on a phone. `residential` roads are intentionally
    /// excluded — major named streets/avenues read better as board tiles.
    private static func buildQuery(for box: BoundingBox) -> String {
        let bbox = "\(box.minLat),\(box.minLon),\(box.maxLat),\(box.maxLon)"
        return """
        [out:json][timeout:25];
        (
          way["highway"~"^(motorway|trunk|primary|secondary)$"]["name"](\(bbox));
        );
        out center 300;
        (
          node["railway"="station"]["name"](\(bbox));
          node["station"="subway"]["name"](\(bbox));
        );
        out center 120;
        (
          node["tourism"="attraction"]["name"](\(bbox));
          way["aeroway"="aerodrome"]["name"](\(bbox));
          node["aeroway"="aerodrome"]["name"](\(bbox));
        );
        out center 60;
        """
    }
}

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let type: String
    let lat: Double?
    let lon: Double?
    let center: Center?
    let tags: [String: String]?

    struct Center: Decodable {
        let lat: Double
        let lon: Double
    }

    func toPlace() -> OverpassPlace? {
        guard let tags, let name = tags["name"], !name.isEmpty else { return nil }
        guard let latitude = lat ?? center?.lat, let longitude = lon ?? center?.lon else { return nil }

        if let highway = tags["highway"] {
            return OverpassPlace(name: name, kind: .road(highwayClass: highway), latitude: latitude, longitude: longitude)
        }
        if tags["railway"] == "station" || tags["station"] == "subway" {
            return OverpassPlace(name: name, kind: .station, latitude: latitude, longitude: longitude)
        }
        if tags["tourism"] == "attraction" || tags["aeroway"] == "aerodrome" {
            return OverpassPlace(name: name, kind: .landmark, latitude: latitude, longitude: longitude)
        }
        return nil
    }
}
