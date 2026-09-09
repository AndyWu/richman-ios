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
