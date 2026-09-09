import Foundation
import RichmanCore

/// Turns a flat list of OSM places into a `Board` shaped by
/// `BoardTemplate.classicSlotOrder`, so it slots into `GameState` exactly
/// like `StandardBoard.classic40Tile()` does — just with real names.
enum BoardLayoutBuilder {
    static func makeBoard(center: (lat: Double, lon: Double), places: [OverpassPlace]) -> Board {
        let propertyNames = pad(
            rankedRoadNames(from: places, center: center),
            to: BoardTemplate.propertyCount,
            fallbackPrefix: "Local Road"
        )
        let stationNames = pad(
            rankedStationNames(from: places, center: center),
            to: BoardTemplate.transitCount,
            fallbackPrefix: "Local Transit Stop"
        )
        let landmarkNames = pad(
            rankedLandmarkNames(from: places, center: center),
            to: BoardTemplate.utilityCount,
            fallbackPrefix: "Landmark"
        )

        var propertyIndex = 0
        var stationIndex = 0
        var landmarkIndex = 0

        let tiles: [Tile] = BoardTemplate.classicSlotOrder.enumerated().map { position, slot in
            switch slot {
            case .go: return Tile(id: position, name: "Go", category: .go)
            case .jail: return Tile(id: position, name: "Jail", category: .jail)
            case .freeParking: return Tile(id: position, name: "Free Parking", category: .freeParking)
            case .goToJail: return Tile(id: position, name: "Go To Jail", category: .goToJail)
            case .tax(let amount):
                return Tile(id: position, name: amount >= 200 ? "Income Tax" : "Luxury Tax", category: .tax(amount: amount))
            case .chance:
                return Tile(id: position, name: "Chance", category: .chance)
            case .communityChest:
                return Tile(id: position, name: "Community Chest", category: .communityChest)
            case .transit:
                defer { stationIndex += 1 }
                return Tile(id: position, name: stationNames[stationIndex], category: .transit(BoardTemplate.transitDetails()))
            case .utility:
                defer { landmarkIndex += 1 }
                return Tile(id: position, name: landmarkNames[landmarkIndex], category: .utility(BoardTemplate.utilityDetails()))
            case .property(let group, let indexInGroup):
                defer { propertyIndex += 1 }
                let name = propertyNames[propertyIndex]
                return Tile(id: position, name: name, category: .property(
                    BoardTemplate.propertyDetails(colorGroupName: colorGroupLabel(group: group, names: propertyNames), group: group, indexInGroup: indexInGroup)
                ))
            }
        }
        return Board(tiles: tiles)
    }

    /// Distinct road names, farthest-from-center first (so the classic
    /// "cheap tiles near Go, expensive tiles near the far corner" pricing
    /// ramp puts a real dollar premium on the city center — same idea the
    /// original 大富翁 boards use with landmark clustering).
    private static func rankedRoadNames(from places: [OverpassPlace], center: (lat: Double, lon: Double)) -> [String] {
        let roads = places.compactMap { place -> (name: String, distance: Double)? in
            guard case .road = place.kind else { return nil }
            return (place.name, distance(from: center, to: (place.latitude, place.longitude)))
        }
        return dedupeFarthestFirst(roads)
    }

    private static func rankedStationNames(from places: [OverpassPlace], center: (lat: Double, lon: Double)) -> [String] {
        let stations = places.compactMap { place -> (name: String, distance: Double)? in
            guard case .station = place.kind else { return nil }
            return (place.name, distance(from: center, to: (place.latitude, place.longitude)))
        }
        // Major stations tend to cluster centrally — closest first.
        return dedupeClosestFirst(stations)
    }

    private static func rankedLandmarkNames(from places: [OverpassPlace], center: (lat: Double, lon: Double)) -> [String] {
        let landmarks = places.compactMap { place -> (name: String, distance: Double)? in
            guard case .landmark = place.kind else { return nil }
            return (place.name, distance(from: center, to: (place.latitude, place.longitude)))
        }
        return dedupeClosestFirst(landmarks)
    }

    private static func dedupeFarthestFirst(_ items: [(name: String, distance: Double)]) -> [String] {
        dedupe(items).sorted { $0.distance > $1.distance }.map(\.name)
    }

    private static func dedupeClosestFirst(_ items: [(name: String, distance: Double)]) -> [String] {
        dedupe(items).sorted { $0.distance < $1.distance }.map(\.name)
    }

    private static func dedupe(_ items: [(name: String, distance: Double)]) -> [(name: String, distance: Double)] {
        var seen = Set<String>()
        var result: [(name: String, distance: Double)] = []
        for item in items where !seen.contains(item.name.lowercased()) {
            seen.insert(item.name.lowercased())
            result.append(item)
        }
        return result
    }

    private static func pad(_ names: [String], to count: Int, fallbackPrefix: String) -> [String] {
        var result = Array(names.prefix(count))
        var n = result.count + 1
        while result.count < count {
            result.append("\(fallbackPrefix) \(n)")
            n += 1
        }
        return result
    }

    /// Names a color group after its first property (e.g. two adjacent tiles
    /// named "5th Avenue" and "6th Avenue" become the "5th Avenue" group).
    private static func colorGroupLabel(group: Int, names: [String]) -> String {
        let sizes = BoardTemplate.colorGroupSizes
        let start = sizes.prefix(group).reduce(0, +)
        return names.indices.contains(start) ? "\(names[start]) District" : "District \(group + 1)"
    }

    /// Flat-earth approximation — plenty accurate at city scale and avoids
    /// pulling in CoreLocation (keeps this package UIKit/CoreLocation-free).
    private static func distance(from a: (lat: Double, lon: Double), to b: (Double, Double)) -> Double {
        let dLat = a.lat - b.0
        let dLon = (a.lon - b.1) * cos(a.lat * .pi / 180)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}
