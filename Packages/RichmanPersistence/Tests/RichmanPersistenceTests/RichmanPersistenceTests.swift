import XCTest
import RichmanCore
import RichmanCityData
@testable import RichmanPersistence

final class RichmanPersistenceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RichmanPersistenceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - GameStateStore

    func testSaveThenLoadRoundTripsGameState() throws {
        let store = GameStateStore(directory: tempDirectory)
        let state = GameState.newGame(board: StandardBoard.classic40Tile(), playerNames: ["A", "B"])

        try store.save(state)
        let loaded = try store.load()

        XCTAssertEqual(loaded, state)
    }

    func testLoadReturnsNilWhenNothingSaved() throws {
        let store = GameStateStore(directory: tempDirectory)
        XCTAssertNil(try store.load())
        XCTAssertFalse(store.hasSavedGame())
    }

    func testDeleteRemovesSavedGame() throws {
        let store = GameStateStore(directory: tempDirectory)
        let state = GameState.newGame(board: StandardBoard.classic40Tile(), playerNames: ["A", "B"])
        try store.save(state)
        XCTAssertTrue(store.hasSavedGame())

        try store.delete()

        XCTAssertFalse(store.hasSavedGame())
        XCTAssertNil(try store.load())
    }

    func testSlotsAreIndependent() throws {
        let store = GameStateStore(directory: tempDirectory)
        let stateA = GameState.newGame(board: StandardBoard.classic40Tile(), playerNames: ["A"])
        let stateB = GameState.newGame(board: StandardBoard.classic40Tile(), playerNames: ["B", "C"])

        try store.save(stateA, slot: "slotA")
        try store.save(stateB, slot: "slotB")

        XCTAssertEqual(try store.load(slot: "slotA"), stateA)
        XCTAssertEqual(try store.load(slot: "slotB"), stateB)
    }

    // MARK: - CityLayoutCache

    func testStoreThenLayoutRoundTripsCityBoardLayout() throws {
        let cache = CityLayoutCache(directory: tempDirectory)
        let layout = CityBoardLayout(queriedName: "New York", resolvedDisplayName: "New York, USA", board: StandardBoard.classic40Tile())

        try cache.store(layout, for: "New York")
        let loaded = cache.layout(for: "New York")

        XCTAssertEqual(loaded, layout)
    }

    func testCityLayoutLookupIsCaseAndWhitespaceInsensitive() throws {
        let cache = CityLayoutCache(directory: tempDirectory)
        let layout = CityBoardLayout(queriedName: "New York", resolvedDisplayName: "New York, USA", board: StandardBoard.classic40Tile())

        try cache.store(layout, for: "New York")

        XCTAssertEqual(cache.layout(for: "  NEW YORK  "), layout)
    }

    func testMissingCityLayoutReturnsNil() {
        let cache = CityLayoutCache(directory: tempDirectory)
        XCTAssertNil(cache.layout(for: "Nowhere"))
    }

    func testClearRemovesCachedLayout() throws {
        let cache = CityLayoutCache(directory: tempDirectory)
        let layout = CityBoardLayout(queriedName: "Taipei", resolvedDisplayName: "Taipei, Taiwan", board: StandardBoard.classic40Tile())
        try cache.store(layout, for: "Taipei")

        try cache.clear(cityName: "Taipei")

        XCTAssertNil(cache.layout(for: "Taipei"))
    }

    // MARK: - CachingCityDataProvider

    func testCachingProviderServesFromCacheWithoutCallingUpstreamAgain() async throws {
        let cache = CityLayoutCache(directory: tempDirectory)
        let counter = CallCounter()
        let upstream = MockCityDataProvider(resolvedDisplayName: "Upstream City")
        let countingUpstream = CountingProvider(wrapped: upstream, counter: counter)
        let provider = CachingCityDataProvider(upstream: countingUpstream, cache: cache)

        let first = try await provider.fetchBoardLayout(for: "Anytown")
        let second = try await provider.fetchBoardLayout(for: "Anytown")

        XCTAssertEqual(first.resolvedDisplayName, "Upstream City")
        XCTAssertEqual(second.resolvedDisplayName, "Upstream City")
        let callCount = await counter.count
        XCTAssertEqual(callCount, 1, "second fetch should be served from the on-disk cache")
    }
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct CountingProvider: CityDataProvider {
    let wrapped: CityDataProvider
    let counter: CallCounter

    func fetchBoardLayout(for cityName: String) async throws -> CityBoardLayout {
        await counter.increment()
        return try await wrapped.fetchBoardLayout(for: cityName)
    }
}
