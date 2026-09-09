import Foundation
import RichmanCore

/// Turns a flat list of OSM places into a `Board` shaped by
/// `BoardTemplate.classicSlotOrder` (so it slots into `GameState` exactly
/// like `StandardBoard.classic40Tile()` does, just with real names) *and*
/// lays every tile out at a real `TileMapPosition`, so the board renders as
/// a path tracing the city's actual shape instead of a square — see
/// `Docs/CITY_DATA.md`.
///
/// Positions here are the city's real topology (declutter aside) — turning
/// that into clean horizontal/vertical/45° route segments for a Tube-map
/// look is `RichmanGameUI.BoardView`'s job (it inserts a bend wherever two
/// adjacent tiles' direct line isn't already one of those angles), not
/// this package's. Keeping the two concerns separate means this package
/// stays about *where things really are*.
enum BoardLayoutBuilder {
    static func makeBoard(center: (lat: Double, lon: Double), places: [OverpassPlace]) -> Board {
        let roads = angleSortedPlaces(places, center: center) { if case .road = $0 { return true }; return false }
        let stations = angleSortedPlaces(places, center: center) { if case .station = $0 { return true }; return false }
        let landmarks = angleSortedPlaces(places, center: center) { if case .landmark = $0 { return true }; return false }

        var roadIterator = roads.makeIterator()
        var stationIterator = stations.makeIterator()
        var landmarkIterator = landmarks.makeIterator()
        var roadPadCount = 0
        var stationPadCount = 0
        var landmarkPadCount = 0
        var propertyNamesInOrder: [String] = []
        var coordinatesByIndex: [Int: (lat: Double, lon: Double)] = [:]

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
                let name: String
                if let station = stationIterator.next() {
                    coordinatesByIndex[position] = (station.lat, station.lon)
                    name = station.name
                } else {
                    stationPadCount += 1
                    name = "Local Transit Stop \(stationPadCount)"
                }
                return Tile(id: position, name: name, category: .transit(BoardTemplate.transitDetails()))
            case .utility:
                let name: String
                if let landmark = landmarkIterator.next() {
                    coordinatesByIndex[position] = (landmark.lat, landmark.lon)
                    name = landmark.name
                } else {
                    landmarkPadCount += 1
                    name = "Landmark \(landmarkPadCount)"
                }
                return Tile(id: position, name: name, category: .utility(BoardTemplate.utilityDetails()))
            case .property(let group, let indexInGroup):
                let name: String
                if let road = roadIterator.next() {
                    coordinatesByIndex[position] = (road.lat, road.lon)
                    name = road.name
                } else {
                    roadPadCount += 1
                    name = "Local Road \(roadPadCount)"
                }
                propertyNamesInOrder.append(name)
                return Tile(id: position, name: name, category: .property(
                    BoardTemplate.propertyDetails(
                        colorGroupName: colorGroupLabel(group: group, names: propertyNamesInOrder),
                        group: group,
                        indexInGroup: indexInGroup
                    )
                ))
            }
        }

        let knownPositions = normalizedPositions(from: coordinatesByIndex)
        let interpolated = interpolatedPositions(for: tiles.count, known: knownPositions)
        let allPositions = decluttered(interpolated)
        let placedTiles = tiles.map { tile -> Tile in
            var placed = tile
            placed.mapPosition = allPositions[tile.id]
            return placed
        }
        return Board(tiles: placedTiles)
    }

    /// Distinct places of one kind, ordered by polar angle around `center`
    /// (arbitrary start angle, increasing counter-clockwise). Walking the
    /// board's fixed slot order while popping from this list in order means
    /// nearby real places tend to land at nearby board indices — this is
    /// about *selection order* (which name fills which slot), not the visual
    /// layout, which comes from each selected place's own real coordinate.
    private static func angleSortedPlaces(
        _ places: [OverpassPlace],
        center: (lat: Double, lon: Double),
        matching predicate: (OverpassPlace.Kind) -> Bool
    ) -> [(name: String, lat: Double, lon: Double)] {
        var seen = Set<String>()
        var result: [(name: String, lat: Double, lon: Double, angle: Double)] = []
        for place in places where predicate(place.kind) {
            let key = place.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let bearing = angle(from: center, to: (place.latitude, place.longitude))
            result.append((place.name, place.latitude, place.longitude, bearing))
        }
        return result.sorted { $0.angle < $1.angle }.map { ($0.name, $0.lat, $0.lon) }
    }

    /// Bearing from `center` to `point`, in `0..<2π`. Flat-earth
    /// approximation with the standard `cos(lat)` longitude correction —
    /// plenty accurate at city scale and keeps this package free of
    /// CoreLocation/MapKit.
    private static func angle(from center: (lat: Double, lon: Double), to point: (Double, Double)) -> Double {
        let dx = (point.1 - center.lon) * cos(center.lat * .pi / 180)
        let dy = point.0 - center.lat
        let raw = atan2(dy, dx)
        return raw < 0 ? raw + 2 * .pi : raw
    }

    /// Maps real (lat, lon) coordinates onto a 0...1 square, preserving the
    /// real aspect ratio (a tall city stays tall, not stretched square) by
    /// fitting the larger dimension to 0...1 and centering the other.
    private static func normalizedPositions(from coordinates: [Int: (lat: Double, lon: Double)]) -> [Int: TileMapPosition] {
        guard !coordinates.isEmpty else { return [:] }
        let lats = coordinates.values.map(\.lat)
        let lons = coordinates.values.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)

        let width = max((maxLon - minLon) * lonScale, 0.000_001)
        let height = max(maxLat - minLat, 0.000_001)
        let side = max(width, height)
        let xInset = (side - width) / 2
        let yInset = (side - height) / 2

        var result: [Int: TileMapPosition] = [:]
        for (index, coordinate) in coordinates {
            let x = ((coordinate.lon - minLon) * lonScale + xInset) / side
            // Flip: higher latitude (further north) renders nearer the top.
            let y = ((maxLat - coordinate.lat) + yInset) / side
            result[index] = TileMapPosition(x: x, y: y)
        }
        return result
    }

    /// Fills every tile index without a real position (padded properties/
    /// stations/utilities, and every generic tile — Go, Jail, Chance, etc.)
    /// by linearly interpolating between the nearest real positions before
    /// and after it (by board index, wrapping around), so the path has no
    /// gaps.
    private static func interpolatedPositions(for tileCount: Int, known: [Int: TileMapPosition]) -> [Int: TileMapPosition] {
        guard !known.isEmpty else { return [:] }
        var result = known
        for index in 0..<tileCount where known[index] == nil {
            var before = (index - 1 + tileCount) % tileCount
            var stepsBefore = 1
            while known[before] == nil {
                before = (before - 1 + tileCount) % tileCount
                stepsBefore += 1
            }
            var after = (index + 1) % tileCount
            var stepsAfter = 1
            while known[after] == nil {
                after = (after + 1) % tileCount
                stepsAfter += 1
            }
            let beforePosition = known[before]!
            let afterPosition = known[after]!
            let fraction = Double(stepsBefore) / Double(stepsBefore + stepsAfter)
            result[index] = TileMapPosition(
                x: beforePosition.x + (afterPosition.x - beforePosition.x) * fraction,
                y: beforePosition.y + (afterPosition.y - beforePosition.y) * fraction
            )
        }
        return result
    }

    /// Real coordinates can put several tiles very close together (dense
    /// downtown blocks vs. a sprawling suburb) — too close to render as
    /// distinct stops, or for `BoardView`'s bend-insertion to draw a sane
    /// route between them. This nudges any pair closer than `minDistance`
    /// apart, a few passes of simple pairwise repulsion, then re-fits
    /// everything back into 0...1 (with a small margin so edge tiles aren't
    /// clipped). Local declutter, not a reshape — the overall path still
    /// traces the real geography.
    private static func decluttered(
        _ positions: [Int: TileMapPosition],
        minDistance: Double = 0.1,
        iterations: Int = 80
    ) -> [Int: TileMapPosition] {
        guard positions.count > 1 else { return positions }
        var points = positions
        let ids = Array(points.keys)

        for _ in 0..<iterations {
            var movedAny = false
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    guard var a = points[ids[i]], var b = points[ids[j]] else { continue }
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    guard distance < minDistance else { continue }
                    movedAny = true
                    if distance < 0.000_001 {
                        // Exactly coincident — nudge deterministically so the next pass has a direction to push along.
                        b.x += minDistance / 2
                    } else {
                        let push = (minDistance - distance) / 2
                        let ux = dx / distance, uy = dy / distance
                        a.x -= ux * push; a.y -= uy * push
                        b.x += ux * push; b.y += uy * push
                    }
                    points[ids[i]] = a
                    points[ids[j]] = b
                }
            }
            if !movedAny { break }
        }

        return refit(points)
    }

    /// Rescales into `0...1` with a small margin so a tile chip centered at
    /// an edge position doesn't get clipped. Scales `x`/`y` by the *same*
    /// factor (fitting the larger dimension, centering the other) rather
    /// than independently, which would distort the real relative angles
    /// between tiles whenever the bounding box isn't square.
    private static func refit(_ positions: [Int: TileMapPosition], margin: Double = 0.05) -> [Int: TileMapPosition] {
        guard !positions.isEmpty else { return positions }
        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let width = max(maxX - minX, 0.000_001)
        let height = max(maxY - minY, 0.000_001)
        let side = max(width, height)
        let usable = 1 - margin * 2
        let scale = usable / side
        let xInset = (usable - width * scale) / 2
        let yInset = (usable - height * scale) / 2

        return positions.mapValues { position in
            TileMapPosition(
                x: margin + xInset + (position.x - minX) * scale,
                y: margin + yInset + (position.y - minY) * scale
            )
        }
    }

    /// Names a color group after its first property (e.g. two adjacent tiles
    /// named "5th Avenue" and "6th Avenue" become the "5th Avenue" group).
    private static func colorGroupLabel(group: Int, names: [String]) -> String {
        let sizes = BoardTemplate.colorGroupSizes
        let start = sizes.prefix(group).reduce(0, +)
        return names.indices.contains(start) ? "\(names[start]) District" : "District \(group + 1)"
    }
}
