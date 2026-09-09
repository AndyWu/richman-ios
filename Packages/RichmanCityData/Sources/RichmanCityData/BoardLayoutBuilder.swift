import Foundation
import RichmanCore

/// Turns a flat list of OSM places into a `Board` shaped by
/// `BoardTemplate.classicSlotOrder` (so it slots into `GameState` exactly
/// like `StandardBoard.classic40Tile()` does, just with real names) *and*
/// lays every tile out at a real `TileMapPosition`, so the board renders as
/// a path tracing the city's actual shape instead of a square — see
/// `Docs/CITY_DATA.md`.
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

        // Bucketing needs to be centered on where the *selected* tiles
        // actually are, not the city's geocoded query center — real named
        // major roads are frequently skewed toward one side of a city's
        // bounding box, and bucketing around a center far from that cluster
        // packs nearly everything into one or two of the 8 directions
        // instead of spreading across all of them.
        let layoutCenter = centroid(of: coordinatesByIndex.values)
        let polarByIndex = coordinatesByIndex.mapValues { polarCoordinate(from: layoutCenter, to: $0) }
        let interpolated = interpolatedPolar(for: tiles.count, known: polarByIndex)
        let snapped = snappedToCompassDirections(interpolated, tileCount: tiles.count)
        let allPositions = refit(snapped)
        let placedTiles = tiles.map { tile -> Tile in
            var placed = tile
            placed.mapPosition = allPositions[tile.id]
            return placed
        }
        return Board(tiles: placedTiles)
    }

    /// `internal` (not `private`) so `RichmanCityDataTests` can verify the
    /// octilinear-snap guarantee directly against `snappedToCompassDirections`,
    /// before `refit`'s rescale makes "bearing from center" ambiguous from
    /// outside (the center of the *final*, refit board isn't (0.5, 0.5)).
    struct PolarCoordinate {
        var angle: Double // bearing from center, 0..<2π
        var radius: Double // flat-earth distance from center, arbitrary units
    }

    /// Distinct places of one kind, ordered by polar angle around `center`
    /// (arbitrary start angle, increasing counter-clockwise). Walking the
    /// board's fixed slot order while popping from this list in order
    /// produces a path that hugs the outer boundary of the selected
    /// points — a cheap stand-in for real road-network routing.
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
            let polar = polarCoordinate(from: center, to: (place.latitude, place.longitude))
            result.append((place.name, place.latitude, place.longitude, polar.angle))
        }
        return result.sorted { $0.angle < $1.angle }.map { ($0.name, $0.lat, $0.lon) }
    }

    /// Bearing and distance from `center` to `point`. Flat-earth
    /// approximation with the standard `cos(lat)` longitude correction —
    /// plenty accurate at city scale and keeps this package free of
    /// CoreLocation/MapKit.
    private static func polarCoordinate(from center: (lat: Double, lon: Double), to point: (Double, Double)) -> PolarCoordinate {
        let dx = (point.1 - center.lon) * cos(center.lat * .pi / 180)
        let dy = point.0 - center.lat
        let rawAngle = atan2(dy, dx)
        let angle = rawAngle < 0 ? rawAngle + 2 * .pi : rawAngle
        let radius = (dx * dx + dy * dy).squareRoot()
        return PolarCoordinate(angle: angle, radius: radius)
    }

    /// Plain average of a set of (lat, lon) points — the reference point
    /// `snappedToCompassDirections` buckets around.
    private static func centroid(of coordinates: Dictionary<Int, (lat: Double, lon: Double)>.Values) -> (lat: Double, lon: Double) {
        guard !coordinates.isEmpty else { return (0, 0) }
        let count = Double(coordinates.count)
        let lat = coordinates.map(\.lat).reduce(0, +) / count
        let lon = coordinates.map(\.lon).reduce(0, +) / count
        return (lat, lon)
    }

    /// Fills every tile index without a real coordinate (padded
    /// properties/stations/utilities, and every generic tile — Go, Jail,
    /// Chance, etc.) by interpolating between the nearest real coordinates
    /// before and after it (by board index, wrapping around), so the path
    /// has no gaps. Angle is unwrapped across the one point where the loop
    /// crosses back through 0/2π so plain linear interpolation stays
    /// monotonic (angles otherwise increase steadily around the loop, by
    /// construction of `angleSortedPlaces`).
    private static func interpolatedPolar(for tileCount: Int, known: [Int: PolarCoordinate]) -> [Int: PolarCoordinate] {
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
            let beforeValue = known[before]!
            var afterAngle = known[after]!.angle
            if afterAngle < beforeValue.angle {
                afterAngle += 2 * .pi
            }
            let fraction = Double(stepsBefore) / Double(stepsBefore + stepsAfter)
            let angle = beforeValue.angle + (afterAngle - beforeValue.angle) * fraction
            let radius = beforeValue.radius + (known[after]!.radius - beforeValue.radius) * fraction
            result[index] = PolarCoordinate(angle: angle.truncatingRemainder(dividingBy: 2 * .pi), radius: radius)
        }
        return result
    }

    /// The heart of the London-Underground-style look: snap every tile's
    /// bearing to the nearest of 8 compass directions, then place it along
    /// that ray. Because bearing increases monotonically around the loop by
    /// construction, this is a "star-shaped" polar curve — which can never
    /// self-intersect no matter how the radius varies, so there's no need
    /// for the old pairwise-declutter pass.
    ///
    /// Bucket boundaries are chosen by *quantile* (equal tile count per
    /// bucket), not by splitting the circle into equal 45° wedges. Real
    /// selected roads/stations are frequently skewed toward one side of a
    /// city rather than spread evenly in every direction; fixed 45° wedges
    /// would then cram most tiles into one or two directions while the rest
    /// sit nearly empty. Quantile buckets still render at exactly the 8 fixed
    /// compass angles (0°, 45°, 90°, ...) — only *which* real tiles map to
    /// which of those 8 angles adapts to the data, keeping every direction
    /// similarly populated.
    ///
    /// Every tile sharing a ray gets a strictly distinct radius along it,
    /// ordered by real distance from center so closer-to-downtown tiles sit
    /// nearer the hub. That renders as a clean straight segment wherever the
    /// path revisits one ray, the way a Tube map runs a line straight for a
    /// while before bending to the next station's direction.
    static func snappedToCompassDirections(
        _ polar: [Int: PolarCoordinate],
        tileCount: Int
    ) -> [Int: TileMapPosition] {
        guard !polar.isEmpty else { return [:] }
        let directionCount = 8
        let step = 2 * Double.pi / Double(directionCount)
        // Fixed regardless of how many tiles land in the busiest bucket, so
        // the star's overall diameter — and therefore how much `refit`'s
        // later rescale shrinks everything — is predictable, not something
        // that balloons whenever one direction happens to collect more
        // tiles than another.
        let baseRadius = 0.35
        let maxRadius = 1.0

        let sortedAngles = polar.values.map(\.angle).sorted()
        // directionCount - 1 interior cut points split sortedAngles into
        // directionCount equal-count groups.
        let boundaries: [Double] = (1..<directionCount).map { cut in
            let position = Double(cut) * Double(sortedAngles.count) / Double(directionCount)
            let lowerIndex = min(Int(position), sortedAngles.count - 1)
            let fraction = position - Double(lowerIndex)
            let upperIndex = min(lowerIndex + 1, sortedAngles.count - 1)
            return sortedAngles[lowerIndex] + (sortedAngles[upperIndex] - sortedAngles[lowerIndex]) * fraction
        }
        func bucket(forAngle angle: Double) -> Int {
            for (cut, boundary) in boundaries.enumerated() where angle < boundary {
                return cut
            }
            return directionCount - 1
        }

        var indicesByBucket: [Int: [Int]] = [:]
        for index in 0..<tileCount {
            guard let value = polar[index] else { continue }
            indicesByBucket[bucket(forAngle: value.angle), default: []].append(index)
        }

        var result: [Int: TileMapPosition] = [:]
        for (bucket, indices) in indicesByBucket {
            let snappedAngle = Double(bucket) * step
            let orderedIndices = indices.sorted { (polar[$0]?.radius ?? 0) < (polar[$1]?.radius ?? 0) }
            let lastRank = max(orderedIndices.count - 1, 1) // avoid /0 when a bucket has just one tile
            for (rank, index) in orderedIndices.enumerated() {
                let radius = baseRadius + Double(rank) / Double(lastRank) * (maxRadius - baseRadius)
                result[index] = TileMapPosition(
                    x: 0.5 + radius * cos(snappedAngle),
                    // Screen y increases downward; negate so north renders toward the top.
                    y: 0.5 - radius * sin(snappedAngle)
                )
            }
        }
        return result
    }

    /// Rescales into `0...1` with a small margin so a tile chip centered at
    /// an edge position doesn't get clipped. Scales `x`/`y` by the *same*
    /// factor (fitting the larger dimension, centering the other) rather
    /// than independently — independent scaling would stretch the
    /// carefully-snapped 45°/90° angles out of true whenever the bounding
    /// box isn't square, which defeats the entire point of snapping them.
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
