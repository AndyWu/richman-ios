import XCTest
import RichmanCore
import RichmanCityData
@testable import RichmanGameUI

@MainActor
final class RichmanGameUITests: XCTestCase {

    // MARK: - SettingsStore

    func testSettingsStoreDefaultsWhenNothingStored() {
        let defaults = makeEphemeralDefaults()

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.animationSpeed, .medium)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.soundVolume, 0.8)
    }

    func testSettingsStorePersistsChangesAcrossInstances() {
        let defaults = makeEphemeralDefaults()
        let settings = SettingsStore(defaults: defaults)

        settings.animationSpeed = .fast
        settings.theme = .dark
        settings.soundVolume = 0.25

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.animationSpeed, .fast)
        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertEqual(reloaded.soundVolume, 0.25)
    }

    func testAnimationSpeedFastIsQuickerThanSlow() {
        XCTAssertLessThan(AnimationSpeed.fast.hopStepDuration, AnimationSpeed.medium.hopStepDuration)
        XCTAssertLessThan(AnimationSpeed.medium.hopStepDuration, AnimationSpeed.slow.hopStepDuration)
        XCTAssertLessThan(AnimationSpeed.fast.zoomSettleDuration, AnimationSpeed.medium.zoomSettleDuration)
        XCTAssertLessThan(AnimationSpeed.medium.zoomSettleDuration, AnimationSpeed.slow.zoomSettleDuration)
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = "RichmanGameUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    // MARK: - BoardLayoutMath

    func testCornerTilesLandOnGridCorners() {
        XCTAssertTrue(BoardLayoutMath.gridPosition(forTileIndex: 0) == (10, 10))
        XCTAssertTrue(BoardLayoutMath.gridPosition(forTileIndex: 10) == (0, 10))
        XCTAssertTrue(BoardLayoutMath.gridPosition(forTileIndex: 20) == (0, 0))
        XCTAssertTrue(BoardLayoutMath.gridPosition(forTileIndex: 30) == (10, 0))
    }

    func testAllFortyTilesMapToDistinctPerimeterPositions() {
        let positions = (0..<40).map { BoardLayoutMath.gridPosition(forTileIndex: $0) }
        let uniquePositions = Set(positions.map { "\($0.col),\($0.row)" })
        XCTAssertEqual(uniquePositions.count, 40, "every tile should occupy a distinct cell")
        for position in positions {
            let onPerimeter = position.col == 0 || position.col == 10 || position.row == 0 || position.row == 10
            XCTAssertTrue(onPerimeter, "tile at \(position) should be on the board's edge")
        }
    }

    // MARK: - RouteGeometry

    func testOctilinearWaypointsPassesThroughAlreadyCleanSegments() {
        let start = CGPoint(x: 10, y: 10)
        XCTAssertEqual(RouteGeometry.octilinearWaypoints(from: start, to: CGPoint(x: 40, y: 10)), [CGPoint(x: 40, y: 10)]) // horizontal
        XCTAssertEqual(RouteGeometry.octilinearWaypoints(from: start, to: CGPoint(x: 10, y: 40)), [CGPoint(x: 10, y: 40)]) // vertical
        XCTAssertEqual(RouteGeometry.octilinearWaypoints(from: start, to: CGPoint(x: 40, y: 40)), [CGPoint(x: 40, y: 40)]) // 45°
        XCTAssertEqual(RouteGeometry.octilinearWaypoints(from: start, to: CGPoint(x: -20, y: 40)), [CGPoint(x: -20, y: 40)]) // 135°
    }

    func testOctilinearWaypointsInsertsExactlyOneBendForAnArbitraryAngle() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 30)

        let waypoints = RouteGeometry.octilinearWaypoints(from: start, to: end)

        XCTAssertEqual(waypoints.count, 2, "an off-angle segment needs exactly one bend point plus the endpoint")
        let bend = waypoints[0]
        XCTAssertEqual(waypoints[1], end)
        // The diagonal leg (start -> bend) must be exactly 45°...
        XCTAssertEqual(abs(bend.x - start.x), abs(bend.y - start.y), accuracy: 0.001)
        // ...and the remaining leg (bend -> end) must be purely horizontal or vertical.
        let remainingIsAxisAligned = bend.x == end.x || bend.y == end.y
        XCTAssertTrue(remainingIsAxisAligned, "leftover leg from \(bend) to \(end) isn't axis-aligned")
    }

    func testOctilinearWaypointsHandlesAllFourQuadrants() {
        let start = CGPoint(x: 0, y: 0)
        for end in [CGPoint(x: 80, y: 20), CGPoint(x: -80, y: 20), CGPoint(x: 80, y: -20), CGPoint(x: -80, y: -20)] {
            let waypoints = RouteGeometry.octilinearWaypoints(from: start, to: end)
            let bend = waypoints[0]
            XCTAssertEqual(abs(bend.x - start.x), abs(bend.y - start.y), accuracy: 0.001, "diagonal leg not 45° for end=\(end)")
            XCTAssertTrue(bend.x == end.x || bend.y == end.y, "remaining leg not axis-aligned for end=\(end)")
        }
    }

    func testRouteColorsAreDistinctForConsecutiveTilesAndStableForTheSameIndex() {
        let colors = (0..<40).map { RouteGeometry.routeColor(forTileIndex: $0) }
        // Same index always yields the same color (deterministic, not random).
        XCTAssertEqual(RouteGeometry.routeColor(forTileIndex: 17), colors[17])
        // Consecutive indices (the common case — they're the ones drawn next
        // to each other) must not resolve to the exact same color.
        for index in 0..<(colors.count - 1) {
            XCTAssertNotEqual(colors[index], colors[index + 1], "tiles \(index) and \(index + 1) got the same route color")
        }
    }

    func testIntermediateStopsAreEmptyForShortSegments() {
        let stops = RouteGeometry.intermediateStops(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 10, y: 0),
            spacing: 40
        )
        XCTAssertTrue(stops.isEmpty)
    }

    func testIntermediateStopsAppearAndStayOnPathForLongSegments() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 300, y: 0)
        let spacing: CGFloat = 40

        let stops = RouteGeometry.intermediateStops(from: start, to: end, spacing: spacing)

        XCTAssertFalse(stops.isEmpty, "a 300pt leg with 40pt spacing should get intermediate stops")
        for stop in stops {
            XCTAssertTrue((0...300).contains(stop.x), "stop \(stop) fell outside the segment")
            XCTAssertEqual(stop.y, 0, accuracy: 0.01, "stop \(stop) drifted off this horizontal segment")
        }
        // Stops should be in increasing order along the path, not clustered or reversed.
        XCTAssertEqual(stops.map(\.x), stops.map(\.x).sorted())
    }

    func testDeclutteredPositionsSeparatesCoincidentAndNearbyPoints() {
        let points = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 100), // exactly coincident with the above
            CGPoint(x: 105, y: 102), // just a few points from the above two
            CGPoint(x: 500, y: 500), // already far from everything else
        ]

        let spaced = RouteGeometry.declutteredPositions(points, minDistance: 40)

        for i in spaced.indices {
            for j in spaced.indices where j > i {
                let distance = hypot(spaced[j].x - spaced[i].x, spaced[j].y - spaced[i].y)
                XCTAssertGreaterThanOrEqual(distance, 40 - 0.01, "points \(i) and \(j) ended up only \(distance)pt apart")
            }
        }
        // The already-isolated point shouldn't have been dragged elsewhere.
        XCTAssertEqual(spaced[3], CGPoint(x: 500, y: 500))
    }

    func testDeclutteredPositionsLeavesAlreadySpacedPointsUntouched() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 0, y: 200)]

        let spaced = RouteGeometry.declutteredPositions(points, minDistance: 40)

        XCTAssertEqual(spaced, points)
    }

    func testDeclutteredPositionsRespectsBoundsWhileStayingSeparated() {
        // A tight cluster jammed into a corner: there's only just enough
        // room in `bounds` to keep all four points the minimum distance
        // apart, so this also exercises the re-clamp-every-iteration path.
        let points = [
            CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 6, y: 5), CGPoint(x: 5, y: 6),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let spaced = RouteGeometry.declutteredPositions(points, minDistance: 40, bounds: bounds)

        for point in spaced {
            XCTAssertTrue(bounds.contains(point), "\(point) fell outside the allowed bounds")
        }
        for i in spaced.indices {
            for j in spaced.indices where j > i {
                let distance = hypot(spaced[j].x - spaced[i].x, spaced[j].y - spaced[i].y)
                XCTAssertGreaterThanOrEqual(distance, 40 - 0.01, "points \(i) and \(j) ended up only \(distance)pt apart")
            }
        }
    }

    // MARK: - GameViewModel.hopPath

    func testHopPathWalksForwardOneTileAtATimeWithWraparound() {
        XCTAssertEqual(GameViewModel.hopPath(from: 5, to: 8, tileCount: 40), [6, 7, 8])
        XCTAssertEqual(GameViewModel.hopPath(from: 38, to: 2, tileCount: 40), [39, 0, 1, 2], "should wrap past the last tile back to 0")
        XCTAssertEqual(GameViewModel.hopPath(from: 5, to: 5, tileCount: 40), [5], "landing back on the same tile still yields one step")
    }

    // MARK: - GameViewModel

    func testStartGameWithNoCityUsesStandardBoard() async {
        let viewModel = GameViewModel(cityDataProvider: MockCityDataProvider())

        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])

        XCTAssertEqual(viewModel.board?.tileCount, 40)
        XCTAssertEqual(viewModel.state?.players.count, 2)
        XCTAssertNil(viewModel.cityLoadMessage)
    }

    func testStartGameWithCityUsesProvidedBoardAndMessage() async {
        let customBoard = StandardBoard.classic40Tile()
        let provider = MockCityDataProvider(board: customBoard, resolvedDisplayName: "Testville, TS")
        let viewModel = GameViewModel(cityDataProvider: provider)

        await viewModel.startGame(cityName: "testville", playerNames: ["A", "B"])

        XCTAssertEqual(viewModel.board, customBoard)
        XCTAssertEqual(viewModel.cityLoadMessage, "Playing in Testville, TS")
    }

    func testStartGameFallsBackToStandardBoardOnCityError() async {
        let provider = MockCityDataProvider(throwing: .cityNotFound("Nowhere"))
        let viewModel = GameViewModel(cityDataProvider: provider)

        await viewModel.startGame(cityName: "Nowhere", playerNames: ["A", "B"])

        XCTAssertEqual(viewModel.board?.tileCount, 40)
        XCTAssertNotNil(viewModel.cityLoadMessage)
    }

    func testRollDiceProducesEventLogAndTracksLastRoll() async {
        let viewModel = GameViewModel(
            cityDataProvider: MockCityDataProvider(),
            makeDiceRoller: { ScriptedDiceRoller(rolls: [DiceRoll(die1: 2, die2: 3)]) }
        )
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])

        await viewModel.rollDice(hopStepDuration: 0, zoomSettleDuration: 0)

        XCTAssertEqual(viewModel.lastRoll, DiceRoll(die1: 2, die2: 3))
        XCTAssertFalse(viewModel.eventLog.isEmpty)
    }

    func testRollDiceOnlyMovesOncePerTurnEvenIfCalledRepeatedly() async {
        let viewModel = GameViewModel(
            cityDataProvider: MockCityDataProvider(),
            // Total 4 lands on the standard board's tax tile (index 4) — no
            // purchase dialog, no card draw, so nothing blocks endTurn().
            makeDiceRoller: { ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 3)]) }
        )
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])

        XCTAssertFalse(viewModel.hasRolledThisTurn)
        await viewModel.rollDice(hopStepDuration: 0, zoomSettleDuration: 0)
        XCTAssertTrue(viewModel.hasRolledThisTurn)
        let positionAfterFirstRoll = viewModel.state?.players[0].position

        // Simulates the reported bug: tapping "Roll Dice" again before "End Turn".
        await viewModel.rollDice(hopStepDuration: 0, zoomSettleDuration: 0)
        await viewModel.rollDice(hopStepDuration: 0, zoomSettleDuration: 0)

        XCTAssertEqual(viewModel.state?.players[0].position, positionAfterFirstRoll, "repeated rolls in one turn must not move the player further")

        viewModel.endTurn()
        XCTAssertFalse(viewModel.hasRolledThisTurn, "a fresh turn should allow rolling again")
    }

    func testBuyingPendingTileClearsPendingState() async {
        let viewModel = GameViewModel(
            cityDataProvider: MockCityDataProvider(),
            makeDiceRoller: { ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]) } // moves onto a property tile
        )
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])

        await viewModel.rollDice(hopStepDuration: 0, zoomSettleDuration: 0)
        XCTAssertNotNil(viewModel.pendingPurchaseTileID)

        viewModel.buyPendingTile()

        XCTAssertNil(viewModel.pendingPurchaseTileID)
    }

    func testRollDiceAnimatesThenSettlesCameraAndPendingPurchase() async {
        let viewModel = GameViewModel(
            cityDataProvider: MockCityDataProvider(),
            makeDiceRoller: { ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]) } // lands on a property tile
        )
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])

        await viewModel.rollDice(hopStepDuration: 0, zoomSettleDuration: 0)

        XCTAssertNil(viewModel.cameraFocusTileID, "camera should be back at the overview once the move finishes")
        XCTAssertFalse(viewModel.isAnimatingMove)
        XCTAssertNotNil(viewModel.pendingPurchaseTileID, "the purchase prompt should only appear once the token has finished moving")
        XCTAssertEqual(viewModel.displayPlayers, viewModel.state?.players ?? [], "once settled, the displayed positions should match the real ones")
    }

    func testRestartToCityPickerClearsGameState() async {
        let viewModel = GameViewModel(cityDataProvider: MockCityDataProvider())
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])
        XCTAssertNotNil(viewModel.state)

        viewModel.restartToCityPicker()

        XCTAssertNil(viewModel.state)
        XCTAssertNil(viewModel.board)
        XCTAssertTrue(viewModel.eventLog.isEmpty)
        XCTAssertNil(viewModel.pendingPurchaseTileID)
    }

    func testEndTurnAdvancesCurrentPlayer() async {
        let viewModel = GameViewModel(cityDataProvider: MockCityDataProvider())
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])
        XCTAssertEqual(viewModel.state?.currentPlayerIndex, 0)

        viewModel.endTurn()

        XCTAssertEqual(viewModel.state?.currentPlayerIndex, 1)
    }
}
