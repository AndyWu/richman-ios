import Foundation

/// Drives a `GameState` through turns: rolling, moving, resolving whatever
/// tile a player lands on, and applying card effects. `RichmanGameUI` is the
/// only consumer that should call these methods; nothing here touches SwiftUI.
///
/// Typical turn from the UI's perspective:
/// 1. If `state.currentPlayer.isInJail`, optionally call `payToLeaveJail()` or
///    `useGetOutOfJailFreeCard()` first.
/// 2. Call `takeTurn()`. Play the returned events (dice, movement, rent, etc.).
/// 3. If `pendingPurchaseTileID` is set, ask the player to buy or not, then
///    call `purchasePendingTile()` or `declinePendingTile()`.
/// 4. Optionally call `buildHouse(atTileID:)` for any properties the player owns.
/// 5. Call `endTurn()`.
public final class GameEngine {
    public private(set) var state: GameState
    private var diceRoller: DiceRoller

    /// Set after `takeTurn()` when the current player lands on an unowned
    /// ownable tile. `endTurn()` refuses to advance while this is non-nil.
    public private(set) var pendingPurchaseTileID: Int?

    /// Set as soon as the current player rolls; `takeTurn()` refuses to roll
    /// again until `endTurn()` resets it for the next player. Without this,
    /// nothing stopped a player from calling `takeTurn()` repeatedly in a
    /// single turn and walking all the way around the board before ever
    /// ending it.
    public private(set) var hasRolledThisTurn = false

    public init(state: GameState, diceRoller: DiceRoller = SystemDiceRoller()) {
        self.state = state
        self.diceRoller = diceRoller
    }

    public var pendingPurchasePrice: Int? {
        pendingPurchaseTileID.map { purchasePrice(forTileAt: $0) }
    }

    // MARK: - Turn actions

    @discardableResult
    public func takeTurn() -> [GameEvent] {
        guard !state.isGameOver, pendingPurchaseTileID == nil, !hasRolledThisTurn else { return [] }
        let playerIndex = state.currentPlayerIndex
        let playerID = state.players[playerIndex].id

        hasRolledThisTurn = true
        let roll = diceRoller.roll()
        var events: [GameEvent] = [.diceRolled(playerID: playerID, roll: roll)]

        if state.players[playerIndex].isInJail {
            let (jailEvents, shouldMoveThisRoll) = resolveJailAttempt(playerIndex: playerIndex, roll: roll)
            events.append(contentsOf: jailEvents)
            guard shouldMoveThisRoll else { return events }
        }

        events.append(contentsOf: moveCurrentPlayer(playerIndex: playerIndex, spaces: roll.total))
        if !state.isGameOver {
            events.append(contentsOf: resolveLanding(playerIndex: playerIndex, diceRoll: roll))
        }
        return events
    }

    @discardableResult
    public func payToLeaveJail() -> [GameEvent] {
        let playerIndex = state.currentPlayerIndex
        guard state.players[playerIndex].isInJail else { return [] }
        let fine = 50
        var events = chargePlayer(at: playerIndex, amount: fine, creditorID: nil, reason: "Paid to leave jail")
        state.players[playerIndex].isInJail = false
        state.players[playerIndex].jailTurnsRemaining = 0
        events.append(.releasedFromJail(playerID: state.players[playerIndex].id, method: .paidFine(fine)))
        return events
    }

    @discardableResult
    public func useGetOutOfJailFreeCard() -> Bool {
        let playerIndex = state.currentPlayerIndex
        guard state.players[playerIndex].isInJail, state.players[playerIndex].getOutOfJailFreeCards > 0 else {
            return false
        }
        state.players[playerIndex].getOutOfJailFreeCards -= 1
        state.players[playerIndex].isInJail = false
        state.players[playerIndex].jailTurnsRemaining = 0
        return true
    }

    @discardableResult
    public func purchasePendingTile() -> [GameEvent] {
        guard let tileIndex = pendingPurchaseTileID else { return [] }
        let playerIndex = state.currentPlayerIndex
        let price = purchasePrice(forTileAt: tileIndex)
        guard state.players[playerIndex].cash >= price else { return [] }
        state.players[playerIndex].cash -= price
        state.tileStates[tileIndex].ownerID = state.players[playerIndex].id
        pendingPurchaseTileID = nil
        return [
            .cashChanged(playerID: state.players[playerIndex].id, delta: -price, reason: "Purchase"),
            .tilePurchased(playerID: state.players[playerIndex].id, tileID: tileIndex, price: price)
        ]
    }

    public func declinePendingTile() {
        // v1: no auction — the tile simply stays unowned. A future version
        // can add an auction phase here without changing this method's signature.
        pendingPurchaseTileID = nil
    }

    @discardableResult
    public func buildHouse(atTileID tileID: Int) -> [GameEvent] {
        let playerIndex = state.currentPlayerIndex
        let playerID = state.players[playerIndex].id
        guard case .property(let details) = state.board.tile(at: tileID).category else { return [] }
        guard state.tileStates[tileID].ownerID == playerID, !state.tileStates[tileID].isMortgaged else { return [] }

        let groupIndices = state.board.propertyIndices(inColorGroup: details.colorGroup)
        guard groupIndices.allSatisfy({ state.tileStates[$0].ownerID == playerID }) else { return [] }

        let currentLevel = state.tileStates[tileID].buildingLevel
        guard currentLevel < 5 else { return [] }
        // Even-building rule: can't build here past the least-built property in the group.
        let minLevelInGroup = groupIndices.map { state.tileStates[$0].buildingLevel }.min() ?? 0
        guard currentLevel == minLevelInGroup else { return [] }
        guard state.players[playerIndex].cash >= details.houseCost else { return [] }

        state.players[playerIndex].cash -= details.houseCost
        state.tileStates[tileID].buildingLevel += 1
        return [
            .cashChanged(playerID: playerID, delta: -details.houseCost, reason: "Building"),
            .houseBuilt(playerID: playerID, tileID: tileID, newLevel: state.tileStates[tileID].buildingLevel)
        ]
    }

    @discardableResult
    public func endTurn() -> [GameEvent] {
        guard !state.isGameOver, pendingPurchaseTileID == nil else { return [] }
        let count = state.players.count
        var nextIndex = state.currentPlayerIndex
        repeat {
            nextIndex = (nextIndex + 1) % count
        } while state.players[nextIndex].isBankrupt && nextIndex != state.currentPlayerIndex
        state.currentPlayerIndex = nextIndex
        hasRolledThisTurn = false
        return [.turnEnded(nextPlayerID: state.players[nextIndex].id)]
    }

    // MARK: - Jail

    /// Returns the events produced, and whether the player should move this roll
    /// (only true when they rolled doubles to escape).
    private func resolveJailAttempt(playerIndex: Int, roll: DiceRoll) -> ([GameEvent], Bool) {
        let playerID = state.players[playerIndex].id
        if roll.isDouble {
            state.players[playerIndex].isInJail = false
            state.players[playerIndex].jailTurnsRemaining = 0
            return ([.releasedFromJail(playerID: playerID, method: .rolledDoubles)], true)
        }
        state.players[playerIndex].jailTurnsRemaining -= 1
        if state.players[playerIndex].jailTurnsRemaining <= 0 {
            let fine = 50
            var events = chargePlayer(at: playerIndex, amount: fine, creditorID: nil, reason: "Jail fine (3rd attempt)")
            state.players[playerIndex].isInJail = false
            events.append(.releasedFromJail(playerID: playerID, method: .paidFine(fine)))
            return (events, false)
        }
        return ([], false)
    }

    private func sendToJail(playerIndex: Int) -> [GameEvent] {
        guard let jailIndex = state.board.tiles.firstIndex(where: {
            if case .jail = $0.category { return true }
            return false
        }) else {
            return []
        }
        state.players[playerIndex].position = jailIndex
        state.players[playerIndex].isInJail = true
        state.players[playerIndex].jailTurnsRemaining = 3
        return [.sentToJail(playerID: state.players[playerIndex].id)]
    }

    // MARK: - Movement

    private func moveCurrentPlayer(playerIndex: Int, spaces: Int) -> [GameEvent] {
        let from = state.players[playerIndex].position
        let destination = from + spaces
        return moveCurrentPlayer(
            playerIndex: playerIndex,
            to: destination % state.board.tileCount,
            collectGoIfPassed: destination >= state.board.tileCount
        )
    }

    private func moveCurrentPlayer(playerIndex: Int, to destination: Int, collectGoIfPassed: Bool) -> [GameEvent] {
        let tileCount = state.board.tileCount
        let from = state.players[playerIndex].position
        let normalizedDestination = ((destination % tileCount) + tileCount) % tileCount
        let playerID = state.players[playerIndex].id

        state.players[playerIndex].position = normalizedDestination
        var events: [GameEvent] = [.playerMoved(playerID: playerID, from: from, to: normalizedDestination, passedGo: collectGoIfPassed)]
        if collectGoIfPassed {
            events.append(contentsOf: payPlayer(at: playerIndex, amount: 200, reason: "Passed Go"))
        }
        return events
    }

    // MARK: - Landing resolution

    private func resolveLanding(playerIndex: Int, diceRoll: DiceRoll) -> [GameEvent] {
        let position = state.players[playerIndex].position
        let tile = state.board.tile(at: position)
        let playerID = state.players[playerIndex].id

        switch tile.category {
        case .go, .jail, .freeParking:
            return []
        case .goToJail:
            return sendToJail(playerIndex: playerIndex)
        case .tax(let amount):
            var events: [GameEvent] = [.taxPaid(playerID: playerID, amount: amount, tileID: tile.id)]
            events.append(contentsOf: chargePlayer(at: playerIndex, amount: amount, creditorID: nil, reason: "Tax"))
            return events
        case .chance:
            return drawAndApplyCard(playerIndex: playerIndex, deck: .chance, diceRoll: diceRoll)
        case .communityChest:
            return drawAndApplyCard(playerIndex: playerIndex, deck: .communityChest, diceRoll: diceRoll)
        case .property, .transit, .utility:
            return resolveOwnableTile(playerIndex: playerIndex, tileIndex: position, diceRoll: diceRoll)
        }
    }

    private func resolveOwnableTile(playerIndex: Int, tileIndex: Int, diceRoll: DiceRoll) -> [GameEvent] {
        let tileState = state.tileStates[tileIndex]
        let playerID = state.players[playerIndex].id
        guard let ownerID = tileState.ownerID else {
            pendingPurchaseTileID = tileIndex
            return []
        }
        guard ownerID != playerID, !tileState.isMortgaged else { return [] }
        let amount = rentOwed(forTileAt: tileIndex, ownerID: ownerID, diceRoll: diceRoll)
        guard amount > 0 else { return [] }
        var events: [GameEvent] = [.rentPaid(payerID: playerID, ownerID: ownerID, amount: amount, tileID: tileIndex)]
        events.append(contentsOf: chargePlayer(at: playerIndex, amount: amount, creditorID: ownerID, reason: "Rent"))
        return events
    }

    private func rentOwed(forTileAt index: Int, ownerID: Player.ID, diceRoll: DiceRoll) -> Int {
        switch state.board.tile(at: index).category {
        case .property(let details):
            return details.rent(atBuildingLevel: state.tileStates[index].buildingLevel)
        case .transit(let details):
            let ownedCount = state.board.transitIndices.filter { state.tileStates[$0].ownerID == ownerID }.count
            return details.rent(forOwnedCount: ownedCount)
        case .utility(let details):
            let ownedCount = state.board.utilityIndices.filter { state.tileStates[$0].ownerID == ownerID }.count
            return details.rentMultiplier(forOwnedCount: ownedCount) * diceRoll.total
        default:
            return 0
        }
    }

    private func purchasePrice(forTileAt index: Int) -> Int {
        switch state.board.tile(at: index).category {
        case .property(let details): return details.price
        case .transit(let details): return details.price
        case .utility(let details): return details.price
        default: return 0
        }
    }

    // MARK: - Cards

    private func drawAndApplyCard(playerIndex: Int, deck: CardDeckKind, diceRoll: DiceRoll) -> [GameEvent] {
        let playerID = state.players[playerIndex].id
        let effect: CardEffect
        switch deck {
        case .chance: effect = state.chanceDeck.draw()
        case .communityChest: effect = state.communityChestDeck.draw()
        }
        var events: [GameEvent] = [.cardDrawn(playerID: playerID, deck: deck, effect: effect)]
        events.append(contentsOf: applyCardEffect(effect, playerIndex: playerIndex, diceRoll: diceRoll))
        return events
    }

    private func applyCardEffect(_ effect: CardEffect, playerIndex: Int, diceRoll: DiceRoll) -> [GameEvent] {
        switch effect {
        case .collect(let amount):
            return payPlayer(at: playerIndex, amount: amount, reason: "Card")
        case .pay(let amount):
            return chargePlayer(at: playerIndex, amount: amount, creditorID: nil, reason: "Card")
        case .moveToTile(let id, let collectGoIfPassed):
            var events = moveCurrentPlayer(playerIndex: playerIndex, to: id, collectGoIfPassed: collectGoIfPassed)
            events.append(contentsOf: resolveLanding(playerIndex: playerIndex, diceRoll: diceRoll))
            return events
        case .moveRelative(let spaces):
            let tileCount = state.board.tileCount
            let from = state.players[playerIndex].position
            let collectGo = spaces > 0 && (from + spaces) >= tileCount
            var events = moveCurrentPlayer(playerIndex: playerIndex, to: from + spaces, collectGoIfPassed: collectGo)
            events.append(contentsOf: resolveLanding(playerIndex: playerIndex, diceRoll: diceRoll))
            return events
        case .goToJail:
            return sendToJail(playerIndex: playerIndex)
        case .getOutOfJailFree:
            state.players[playerIndex].getOutOfJailFreeCards += 1
            return []
        case .repairs(let perHouse, let perHotel):
            let playerID = state.players[playerIndex].id
            let total = state.tileStates.indices
                .filter { state.tileStates[$0].ownerID == playerID }
                .reduce(0) { partial, index in
                    let level = state.tileStates[index].buildingLevel
                    return partial + (level == 5 ? perHotel : level * perHouse)
                }
            return chargePlayer(at: playerIndex, amount: total, creditorID: nil, reason: "Repairs")
        case .collectFromEachPlayer(let amount):
            let creditorID = state.players[playerIndex].id
            var events: [GameEvent] = []
            for index in state.players.indices where index != playerIndex && !state.players[index].isBankrupt {
                events.append(contentsOf: chargePlayer(at: index, amount: amount, creditorID: creditorID, reason: "Card collection"))
            }
            return events
        case .payToEachPlayer(let amount):
            var events: [GameEvent] = []
            for index in state.players.indices where index != playerIndex && !state.players[index].isBankrupt {
                guard !state.players[playerIndex].isBankrupt else { break }
                events.append(contentsOf: chargePlayer(at: playerIndex, amount: amount, creditorID: state.players[index].id, reason: "Card payment"))
            }
            return events
        }
    }

    // MARK: - Cash transfer & bankruptcy

    private func payPlayer(at playerIndex: Int, amount: Int, reason: String) -> [GameEvent] {
        guard amount != 0 else { return [] }
        state.players[playerIndex].cash += amount
        return [.cashChanged(playerID: state.players[playerIndex].id, delta: amount, reason: reason)]
    }

    /// Debits `amount` from the player at `playerIndex`, crediting `creditorID` if given
    /// (nil means paid to the bank). If the player can't cover it, they go bankrupt:
    /// they pay what they have, the creditor inherits their properties, and the rest
    /// return to the bank.
    private func chargePlayer(at playerIndex: Int, amount: Int, creditorID: Player.ID?, reason: String) -> [GameEvent] {
        guard amount > 0 else { return [] }
        let payerID = state.players[playerIndex].id
        var events: [GameEvent] = []

        if state.players[playerIndex].cash >= amount {
            state.players[playerIndex].cash -= amount
            events.append(.cashChanged(playerID: payerID, delta: -amount, reason: reason))
            if let creditorID, let creditorIndex = state.indexOfPlayer(withID: creditorID) {
                events.append(contentsOf: payPlayer(at: creditorIndex, amount: amount, reason: reason))
            }
            return events
        }

        let partial = max(0, state.players[playerIndex].cash)
        state.players[playerIndex].cash = 0
        if partial > 0 {
            events.append(.cashChanged(playerID: payerID, delta: -partial, reason: reason))
            if let creditorID, let creditorIndex = state.indexOfPlayer(withID: creditorID) {
                events.append(contentsOf: payPlayer(at: creditorIndex, amount: partial, reason: reason))
            }
        }
        state.players[playerIndex].isBankrupt = true
        for index in state.tileStates.indices where state.tileStates[index].ownerID == payerID {
            state.tileStates[index].ownerID = creditorID
            state.tileStates[index].buildingLevel = 0
            state.tileStates[index].isMortgaged = false
        }
        events.append(.playerBankrupted(playerID: payerID, toCreditorID: creditorID))
        events.append(contentsOf: checkForGameOver())
        return events
    }

    private func checkForGameOver() -> [GameEvent] {
        let active = state.activePlayers
        guard active.count <= 1 else { return [] }
        state.isGameOver = true
        return [.gameOver(winnerID: active.first?.id)]
    }
}
