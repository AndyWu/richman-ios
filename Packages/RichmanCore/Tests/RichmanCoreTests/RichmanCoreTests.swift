import XCTest
@testable import RichmanCore

final class RichmanCoreTests: XCTestCase {

    // MARK: - Board

    func testStandardBoardHas40Tiles() {
        let board = StandardBoard.classic40Tile()
        XCTAssertEqual(board.tileCount, 40)
        XCTAssertEqual(board.tiles.first?.category, .go)
    }

    func testStandardBoardTilesHaveNoMapPosition() {
        // No real geography to place them at — RichmanGameUI falls back to the classic square layout.
        let board = StandardBoard.classic40Tile()
        XCTAssertTrue(board.tiles.allSatisfy { $0.mapPosition == nil })
    }

    func testTileMapPositionRoundTripsThroughCodable() throws {
        let tile = Tile(id: 1, name: "Test Ave", category: .go, mapPosition: TileMapPosition(x: 0.25, y: 0.75))
        let data = try JSONEncoder().encode(tile)
        let decoded = try JSONDecoder().decode(Tile.self, from: data)
        XCTAssertEqual(decoded.mapPosition, TileMapPosition(x: 0.25, y: 0.75))
    }

    func testNewGameStartsPlayersAtGoWithTenTimesTheMostExpensivePropertyPrice() {
        let board = StandardBoard.classic40Tile()
        let state = GameState.newGame(board: board, playerNames: ["A", "B"])

        let mostExpensiveProperty = board.tiles.compactMap { tile -> Int? in
            if case .property(let details) = tile.category { return details.price }
            return nil
        }.max()!

        XCTAssertEqual(state.players.count, 2)
        XCTAssertTrue(state.players.allSatisfy { $0.position == 0 && $0.cash == mostExpensiveProperty * 10 })
    }

    // MARK: - Movement & purchase

    func testTakeTurnMovesPlayerAndCollectsGoOnWraparound() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500, position: 8), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]))

        let events = engine.takeTurn()

        XCTAssertTrue(events.contains(.playerMoved(playerID: state.players[0].id, from: 8, to: 1, passedGo: true)))
        XCTAssertTrue(events.contains(.cashChanged(playerID: state.players[0].id, delta: 200, reason: "Passed Go")))
        XCTAssertEqual(engine.state.players[0].cash, 1_700)
        XCTAssertEqual(engine.pendingPurchaseTileID, 1)
        XCTAssertEqual(engine.pendingPurchasePrice, 100)
    }

    func testTakeTurnRefusesToRollAgainUntilEndTurn() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 2, die2: 3)]))

        let firstEvents = engine.takeTurn()
        XCTAssertFalse(firstEvents.isEmpty)
        let positionAfterFirstRoll = engine.state.players[0].position

        // A second roll in the same turn must be a no-op: no events, no further movement —
        // otherwise a player could click "Roll Dice" repeatedly and walk around the board
        // before ever ending their turn.
        let secondEvents = engine.takeTurn()
        XCTAssertTrue(secondEvents.isEmpty, "a second roll in the same turn should do nothing")
        XCTAssertEqual(engine.state.players[0].position, positionAfterFirstRoll)

        engine.endTurn()
        engine.endTurn() // back to A

        // After ending the turn (and cycling back around), rolling again works normally.
        let thirdEvents = engine.takeTurn()
        XCTAssertFalse(thirdEvents.isEmpty, "rolling should work again once it's actually a new turn")
    }

    func testPurchasingPendingTileTransfersOwnershipAndCash() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500, position: 8), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]))
        engine.takeTurn()
        XCTAssertEqual(engine.pendingPurchaseTileID, 1)

        let events = engine.purchasePendingTile()

        XCTAssertNil(engine.pendingPurchaseTileID)
        XCTAssertEqual(engine.state.tileStates[1].ownerID, state.players[0].id)
        XCTAssertEqual(engine.state.players[0].cash, 1_700 - 100)
        XCTAssertTrue(events.contains { if case .tilePurchased(_, 1, 100) = $0 { return true }; return false })
    }

    func testEndTurnRefusesToAdvanceWithPendingPurchase() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500, position: 8), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]))
        engine.takeTurn()
        XCTAssertNotNil(engine.pendingPurchaseTileID)

        let events = engine.endTurn()

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.state.currentPlayerIndex, 0)
    }

    // MARK: - Rent

    func testRentIsChargedToVisitorAndCreditedToOwner() {
        var state = GameState(
            board: TestBoard.make(),
            players: [
                Player(name: "A", cash: 1_500, position: 0),
                Player(name: "B", cash: 1_500, position: 0)
            ],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)]),
            currentPlayerIndex: 1
        )
        let ownerID = state.players[0].id
        state.tileStates[2].ownerID = ownerID // Property B, base rent 12

        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 1)]))
        let events = engine.takeTurn()

        let payerID = state.players[1].id
        XCTAssertTrue(events.contains(.rentPaid(payerID: payerID, ownerID: ownerID, amount: 12, tileID: 2)))
        XCTAssertEqual(engine.state.players[1].cash, 1_500 - 12)
        XCTAssertEqual(engine.state.players[0].cash, 1_500 + 12)
        XCTAssertNil(engine.pendingPurchaseTileID)
    }

    // MARK: - Building

    func testBuildHouseRequiresFullColorGroupAndEvenBuilding() {
        var state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let ownerID = state.players[0].id
        state.tileStates[1].ownerID = ownerID
        state.tileStates[2].ownerID = ownerID
        let engine = GameEngine(state: state)

        // Building tile 1 to level 1 is fine (both properties at level 0).
        XCTAssertFalse(engine.buildHouse(atTileID: 1).isEmpty)
        XCTAssertEqual(engine.state.tileStates[1].buildingLevel, 1)

        // Building tile 1 again is refused: tile 2 is still behind (even-building rule).
        XCTAssertTrue(engine.buildHouse(atTileID: 1).isEmpty)
        XCTAssertEqual(engine.state.tileStates[1].buildingLevel, 1)

        // Catching tile 2 up unblocks tile 1 again.
        XCTAssertFalse(engine.buildHouse(atTileID: 2).isEmpty)
        XCTAssertFalse(engine.buildHouse(atTileID: 1).isEmpty)
        XCTAssertEqual(engine.state.tileStates[1].buildingLevel, 2)
    }

    func testBuildHouseFailsWithoutOwningWholeGroup() {
        var state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        state.tileStates[1].ownerID = state.players[0].id // only Property A, not B
        let engine = GameEngine(state: state)

        XCTAssertTrue(engine.buildHouse(atTileID: 1).isEmpty)
        XCTAssertEqual(engine.state.tileStates[1].buildingLevel, 0)
    }

    // MARK: - Tax & cards

    func testTaxTileChargesPlayer() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 2, die2: 2)]))

        let events = engine.takeTurn()

        XCTAssertTrue(events.contains(.taxPaid(playerID: state.players[0].id, amount: 75, tileID: 4)))
        XCTAssertEqual(engine.state.players[0].cash, 1_500 - 75)
    }

    func testChanceCardCollectEffect() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(50)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]))

        let events = engine.takeTurn()

        XCTAssertTrue(events.contains(.cardDrawn(playerID: state.players[0].id, deck: .chance, effect: .collect(50))))
        XCTAssertEqual(engine.state.players[0].cash, 1_500 + 50)
    }

    func testChanceCardGoToJailEffectSendsPlayerToJail() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.goToJail]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 2)]))

        let events = engine.takeTurn()

        XCTAssertTrue(events.contains(.sentToJail(playerID: state.players[0].id)))
        XCTAssertTrue(engine.state.players[0].isInJail)
        XCTAssertEqual(engine.state.players[0].position, 5)
        XCTAssertEqual(engine.state.players[0].jailTurnsRemaining, 3)
    }

    // MARK: - Jail

    func testRollingDoublesEscapesJailAndMovesThatRoll() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500, position: 5, isInJail: true, jailTurnsRemaining: 3), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 3, die2: 3)]))

        let events = engine.takeTurn()

        XCTAssertFalse(engine.state.players[0].isInJail)
        XCTAssertTrue(events.contains(.releasedFromJail(playerID: state.players[0].id, method: .rolledDoubles)))
        XCTAssertEqual(engine.state.players[0].position, 1) // 5 + 6 = 11, wraps to 1
        XCTAssertEqual(engine.pendingPurchaseTileID, 1)
    }

    func testThreeFailedJailAttemptsForcesFineWithoutMoving() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500, position: 5, isInJail: true, jailTurnsRemaining: 3), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let nonDouble = DiceRoll(die1: 2, die2: 3)
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [nonDouble]))

        engine.takeTurn() // A, attempt 1: remaining 3 -> 2
        XCTAssertTrue(engine.state.players[0].isInJail)
        engine.endTurn() // -> B
        engine.takeTurn() // B's (unrelated) turn
        engine.endTurn() // -> A

        engine.takeTurn() // A, attempt 2: remaining 2 -> 1
        XCTAssertTrue(engine.state.players[0].isInJail)
        engine.endTurn() // -> B
        engine.takeTurn() // B's (unrelated) turn
        engine.endTurn() // -> A

        let finalEvents = engine.takeTurn() // A, attempt 3: forced fine, released, no movement

        XCTAssertFalse(engine.state.players[0].isInJail)
        XCTAssertEqual(engine.state.players[0].position, 5, "should not move on the turn it pays the forced fine")
        XCTAssertEqual(engine.state.players[0].cash, 1_500 - 50)
        XCTAssertTrue(finalEvents.contains(.releasedFromJail(playerID: state.players[0].id, method: .paidFine(50))))
    }

    func testPayToLeaveJailReleasesImmediately() {
        let state = GameState(
            board: TestBoard.make(),
            players: [Player(name: "A", cash: 1_500, position: 5, isInJail: true, jailTurnsRemaining: 3), Player(name: "B", cash: 1_500)],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)])
        )
        let engine = GameEngine(state: state)

        let events = engine.payToLeaveJail()

        XCTAssertFalse(engine.state.players[0].isInJail)
        XCTAssertEqual(engine.state.players[0].cash, 1_500 - 50)
        XCTAssertTrue(events.contains(.releasedFromJail(playerID: state.players[0].id, method: .paidFine(50))))
    }

    // MARK: - Bankruptcy & game over

    func testTaxBankruptsPlayerAndEndsTwoPlayerGame() {
        let state = GameState(
            board: TestBoard.make(),
            players: [
                Player(name: "A", cash: 1_500, position: 0),
                Player(name: "B", cash: 5, position: 0)
            ],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)]),
            currentPlayerIndex: 1
        )
        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 2, die2: 2)]))

        let events = engine.takeTurn()

        let bID = state.players[1].id
        let aID = state.players[0].id
        XCTAssertTrue(events.contains(.playerBankrupted(playerID: bID, toCreditorID: nil)))
        XCTAssertTrue(events.contains(.gameOver(winnerID: aID)))
        XCTAssertTrue(engine.state.isGameOver)
        XCTAssertTrue(engine.state.players[1].isBankrupt)
        XCTAssertEqual(engine.state.players[1].cash, 0)
    }

    func testRentBankruptcyTransfersLoserPropertiesToCreditor() {
        var state = GameState(
            board: TestBoard.make(),
            players: [
                Player(name: "A", cash: 1_500, position: 0),
                Player(name: "B", cash: 5, position: 0)
            ],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)]),
            currentPlayerIndex: 1
        )
        let aID = state.players[0].id
        let bID = state.players[1].id
        state.tileStates[2].ownerID = aID // Property B, base rent 12 > B's cash (5)
        state.tileStates[6].ownerID = bID // B owns the transit tile

        let engine = GameEngine(state: state, diceRoller: ScriptedDiceRoller(rolls: [DiceRoll(die1: 1, die2: 1)]))
        let events = engine.takeTurn()

        XCTAssertTrue(events.contains(.playerBankrupted(playerID: bID, toCreditorID: aID)))
        XCTAssertEqual(engine.state.tileStates[6].ownerID, aID, "B's transit tile should transfer to the creditor")
        XCTAssertEqual(engine.state.players[0].cash, 1_500 + 5, "A only receives what B actually had")
        XCTAssertTrue(engine.state.isGameOver)
    }

    // MARK: - Turn order

    func testEndTurnSkipsBankruptPlayers() {
        let state = GameState(
            board: TestBoard.make(),
            players: [
                Player(name: "A", cash: 1_500),
                Player(name: "B", cash: 0, isBankrupt: true),
                Player(name: "C", cash: 1_500)
            ],
            chanceDeck: CardDeck(cards: [.collect(0)]),
            communityChestDeck: CardDeck(cards: [.collect(0)]),
            currentPlayerIndex: 0
        )
        let engine = GameEngine(state: state)

        let events = engine.endTurn()

        XCTAssertEqual(engine.state.currentPlayerIndex, 2)
        XCTAssertTrue(events.contains(.turnEnded(nextPlayerID: state.players[2].id)))
    }
}
