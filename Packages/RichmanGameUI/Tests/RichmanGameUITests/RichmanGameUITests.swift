import XCTest
import RichmanCore
import RichmanCityData
@testable import RichmanGameUI

@MainActor
final class RichmanGameUITests: XCTestCase {

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

        viewModel.rollDice()

        XCTAssertEqual(viewModel.lastRoll, DiceRoll(die1: 2, die2: 3))
        XCTAssertFalse(viewModel.eventLog.isEmpty)
    }

    func testBuyingPendingTileClearsPendingState() async {
        let viewModel = GameViewModel(
            cityDataProvider: MockCityDataProvider(),
            makeDiceRoller: { ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]) } // moves onto a property tile
        )
        await viewModel.startGame(cityName: nil, playerNames: ["A", "B"])

        viewModel.rollDice()
        XCTAssertNotNil(viewModel.pendingPurchaseTileID)

        viewModel.buyPendingTile()

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
