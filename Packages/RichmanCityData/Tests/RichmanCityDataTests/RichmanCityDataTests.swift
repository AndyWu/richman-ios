import XCTest
import RichmanCore
@testable import RichmanCityData

final class RichmanCityDataTests: XCTestCase {

    // MARK: - BoardLayoutBuilder (pure, no network)

    func testMakeBoardProducesFullyPopulatedFortyTileBoard() {
        // 30 named roads at varying distance from center, 5 stations, 3 landmarks —
        // comfortably more than the board needs, so no padding should kick in.
        var places: [OverpassPlace] = []
        for i in 0..<30 {
            places.append(OverpassPlace(name: "Road \(i)", kind: .road(highwayClass: "primary"), latitude: Double(i) * 0.01, longitude: 0))
        }
        for i in 0..<5 {
            places.append(OverpassPlace(name: "Station \(i)", kind: .station, latitude: Double(i) * 0.01, longitude: 0.01))
        }
        for i in 0..<3 {
            places.append(OverpassPlace(name: "Landmark \(i)", kind: .landmark, latitude: Double(i) * 0.01, longitude: 0.02))
        }

        let board = BoardLayoutBuilder.makeBoard(center: (lat: 0, lon: 0), places: places)

        XCTAssertEqual(board.tileCount, 40)
        let propertyTiles = board.tiles.filter { if case .property = $0.category { return true }; return false }
        let transitTiles = board.tiles.filter { if case .transit = $0.category { return true }; return false }
        let utilityTiles = board.tiles.filter { if case .utility = $0.category { return true }; return false }
        XCTAssertEqual(propertyTiles.count, BoardTemplate.propertyCount)
        XCTAssertEqual(transitTiles.count, BoardTemplate.transitCount)
        XCTAssertEqual(utilityTiles.count, BoardTemplate.utilityCount)
        XCTAssertTrue(propertyTiles.allSatisfy { $0.name.hasPrefix("Road ") })
        XCTAssertTrue(transitTiles.allSatisfy { $0.name.hasPrefix("Station ") })
        XCTAssertTrue(utilityTiles.allSatisfy { $0.name.hasPrefix("Landmark ") })
    }

    func testMakeBoardAssignsAMapPositionToEveryTile() {
        var places: [OverpassPlace] = []
        for i in 0..<30 {
            places.append(OverpassPlace(name: "Road \(i)", kind: .road(highwayClass: "primary"), latitude: Double(i) * 0.01, longitude: Double(i) * 0.005))
        }
        for i in 0..<5 {
            places.append(OverpassPlace(name: "Station \(i)", kind: .station, latitude: Double(i) * 0.01, longitude: 0.01))
        }
        for i in 0..<3 {
            places.append(OverpassPlace(name: "Landmark \(i)", kind: .landmark, latitude: Double(i) * 0.01, longitude: 0.02))
        }

        let board = BoardLayoutBuilder.makeBoard(center: (lat: 0.1, lon: 0.05), places: places)

        XCTAssertEqual(board.tiles.count, 40)
        for tile in board.tiles {
            guard let position = tile.mapPosition else {
                XCTFail("tile \(tile.id) (\(tile.name)) has no mapPosition")
                continue
            }
            XCTAssertTrue((0...1).contains(position.x), "x out of range for tile \(tile.id): \(position.x)")
            XCTAssertTrue((0...1).contains(position.y), "y out of range for tile \(tile.id): \(position.y)")
        }
    }

    func testMakeBoardNeverPlacesTwoTilesAtTheExactSamePosition() {
        var places: [OverpassPlace] = []
        for i in 0..<30 {
            places.append(OverpassPlace(name: "Road \(i)", kind: .road(highwayClass: "primary"), latitude: Double(i) * 0.013, longitude: Double(i) * 0.021))
        }
        for i in 0..<5 {
            places.append(OverpassPlace(name: "Station \(i)", kind: .station, latitude: Double(i) * 0.017, longitude: 0.03 - Double(i) * 0.004))
        }
        for i in 0..<3 {
            places.append(OverpassPlace(name: "Landmark \(i)", kind: .landmark, latitude: 0.02 + Double(i) * 0.009, longitude: 0.025))
        }

        let board = BoardLayoutBuilder.makeBoard(center: (lat: 0.1, lon: 0.05), places: places)

        var seenPositions = Set<String>()
        for tile in board.tiles {
            guard let position = tile.mapPosition else { continue }
            let key = "\(Int((position.x * 10_000).rounded())),\(Int((position.y * 10_000).rounded()))"
            XCTAssertTrue(seenPositions.insert(key).inserted, "tile \(tile.id) (\(tile.name)) exactly overlaps another tile")
        }
    }

    /// Tests `snappedToCompassDirections` directly (bypassing `refit`, which
    /// rescales x/y independently around whatever bounding box the snapped
    /// points end up with — so "bearing from center" isn't observable from
    /// outside the final board without knowing where its center landed).
    /// The snapping math itself always centers on exactly (0.5, 0.5).
    func testSnappedToCompassDirectionsUsesOnlyEightBearings() {
        let polar: [Int: BoardLayoutBuilder.PolarCoordinate] = [
            0: .init(angle: 0.05, radius: 1.0),
            1: .init(angle: 0.5, radius: 1.0),
            2: .init(angle: 1.9, radius: 1.0),
            3: .init(angle: 3.0, radius: 1.0),
            4: .init(angle: 4.4, radius: 1.0),
            5: .init(angle: 5.9, radius: 1.0)
        ]

        let positions = BoardLayoutBuilder.snappedToCompassDirections(polar, tileCount: 6)

        XCTAssertEqual(positions.count, 6)
        let allowedBearingsDegrees: [Double] = (0..<8).map { Double($0) * 45 }
        func circularDistance(_ a: Double, _ b: Double) -> Double {
            let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(diff, 360 - diff)
        }
        for (index, position) in positions {
            let dx = position.x - 0.5
            let dy = position.y - 0.5
            let radius = (dx * dx + dy * dy).squareRoot()
            XCTAssertGreaterThan(radius, 0, "tile \(index) landed exactly on the center")
            var bearing = atan2(-dy, dx) * 180 / .pi // matches the y-flip snappedToCompassDirections applies
            if bearing < 0 { bearing += 360 }
            let deviation = allowedBearingsDegrees.map { circularDistance($0, bearing) }.min()!
            XCTAssertLessThan(deviation, 0.01, "tile \(index) bearing \(bearing)° isn't exactly an octant")
        }
    }

    func testSnappedToCompassDirectionsGivesEveryTileOnTheSameRayADistinctRadius() {
        // 16 evenly-spaced bearings split by quantile into 8 buckets of 2 —
        // whichever tiles land together on a ray must still get distinct radii.
        var polar: [Int: BoardLayoutBuilder.PolarCoordinate] = [:]
        for i in 0..<16 {
            polar[i] = .init(angle: Double(i) * (2 * .pi / 16), radius: 0.5 + Double(i) * 0.01)
        }

        let positions = BoardLayoutBuilder.snappedToCompassDirections(polar, tileCount: 16)

        var radiiByBearing: [Int: Set<Double>] = [:] // keyed by rounded bearing in degrees
        for index in 0..<16 {
            let position = positions[index]!
            let dx = position.x - 0.5
            let dy = position.y - 0.5
            let radius = (dx * dx + dy * dy).squareRoot()
            var bearing = Int((atan2(-dy, dx) * 180 / .pi).rounded())
            if bearing < 0 { bearing += 360 }
            let wasNew = radiiByBearing[bearing, default: []].insert(radius).inserted
            XCTAssertTrue(wasNew, "tile \(index) shares both bearing \(bearing)° and radius \(radius) with another tile")
        }
        // With 16 tiles over 8 rays, at least one ray must carry more than one tile.
        XCTAssertTrue(radiiByBearing.values.contains { $0.count > 1 })
    }

    func testMakeBoardInterpolatesPositionsForPaddedAndGenericTiles() {
        // Only 2 real roads and nothing else — every other tile (padded
        // properties/stations/utilities, plus every generic tile) must still
        // get an interpolated position so the path has no gaps.
        let places = [
            OverpassPlace(name: "Only Road A", kind: .road(highwayClass: "primary"), latitude: 0, longitude: 0),
            OverpassPlace(name: "Only Road B", kind: .road(highwayClass: "secondary"), latitude: 0.02, longitude: 0.01)
        ]

        let board = BoardLayoutBuilder.makeBoard(center: (lat: 0, lon: 0), places: places)

        XCTAssertTrue(board.tiles.allSatisfy { $0.mapPosition != nil })
    }

    func testMakeBoardPadsWhenTooFewRealPlacesAreFound() {
        // Only 2 roads, 0 stations, 0 landmarks — the builder must still produce
        // a complete, playable 40-tile board.
        let places = [
            OverpassPlace(name: "Only Road A", kind: .road(highwayClass: "primary"), latitude: 0, longitude: 0),
            OverpassPlace(name: "Only Road B", kind: .road(highwayClass: "secondary"), latitude: 0.01, longitude: 0)
        ]

        let board = BoardLayoutBuilder.makeBoard(center: (lat: 0, lon: 0), places: places)

        XCTAssertEqual(board.tileCount, 40)
        let propertyNames = Set(board.tiles.compactMap { tile -> String? in
            if case .property = tile.category { return tile.name }
            return nil
        })
        XCTAssertTrue(propertyNames.contains("Only Road A"))
        XCTAssertTrue(propertyNames.contains("Only Road B"))
        XCTAssertTrue(propertyNames.contains { $0.hasPrefix("Local Road") })
    }

    func testMakeBoardDedupesRepeatedNames() {
        let places = (0..<40).map {
            OverpassPlace(name: "Main Street", kind: .road(highwayClass: "primary"), latitude: Double($0) * 0.001, longitude: 0)
        }

        let board = BoardLayoutBuilder.makeBoard(center: (lat: 0, lon: 0), places: places)

        let propertyNames = board.tiles.compactMap { tile -> String? in
            if case .property = tile.category { return tile.name }
            return nil
        }
        XCTAssertEqual(propertyNames.filter { $0 == "Main Street" }.count, 1, "a name repeated across many OSM segments should only fill one tile")
    }

    // MARK: - MockCityDataProvider

    func testMockCityDataProviderReturnsConfiguredBoard() async throws {
        let board = StandardBoard.classic40Tile()
        let provider = MockCityDataProvider(board: board, resolvedDisplayName: "Testville")

        let layout = try await provider.fetchBoardLayout(for: "testville")

        XCTAssertEqual(layout.resolvedDisplayName, "Testville")
        XCTAssertEqual(layout.board, board)
    }

    func testMockCityDataProviderCanThrowConfiguredError() async {
        let provider = MockCityDataProvider(throwing: .cityNotFound("Nowhere"))

        do {
            _ = try await provider.fetchBoardLayout(for: "Nowhere")
            XCTFail("expected an error")
        } catch let error as CityDataError {
            XCTAssertEqual(error, .cityNotFound("Nowhere"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - BundledCityDataProvider

    func testBundledProviderLoadsNewYork() async throws {
        let provider = BundledCityDataProvider()
        let layout = try await provider.fetchBoardLayout(for: "New York")
        XCTAssertEqual(layout.board.tileCount, 40)
        XCTAssertFalse(layout.resolvedDisplayName.isEmpty)
    }

    func testBundledProviderLoadsTaipei() async throws {
        let provider = BundledCityDataProvider()
        let layout = try await provider.fetchBoardLayout(for: "Taipei")
        XCTAssertEqual(layout.board.tileCount, 40)
    }

    func testBundledProviderNormalizesCityNameForLookup() async throws {
        let provider = BundledCityDataProvider()
        let layout = try await provider.fetchBoardLayout(for: "  new york  ")
        XCTAssertEqual(layout.board.tileCount, 40)
    }

    func testBundledProviderFallsBackWhenCityIsNotBundled() async throws {
        let fallback = MockCityDataProvider(resolvedDisplayName: "Fallback City")
        let provider = BundledCityDataProvider(fallback: fallback)

        let layout = try await provider.fetchBoardLayout(for: "Some Unbundled Town")

        XCTAssertEqual(layout.resolvedDisplayName, "Fallback City")
    }

    func testBundledProviderThrowsWithoutFallbackForUnknownCity() async {
        let provider = BundledCityDataProvider()
        do {
            _ = try await provider.fetchBoardLayout(for: "Some Unbundled Town")
            XCTFail("expected cityNotFound")
        } catch let error as CityDataError {
            XCTAssertEqual(error, .cityNotFound("Some Unbundled Town"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
