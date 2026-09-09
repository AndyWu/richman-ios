import Foundation

/// A single thing that happened as a result of a `GameEngine` action, in the
/// order it happened. `RichmanGameUI` turns these into animations/dialogs.
public enum GameEvent: Codable, Equatable, Sendable {
    case diceRolled(playerID: Player.ID, roll: DiceRoll)
    case playerMoved(playerID: Player.ID, from: Int, to: Int, passedGo: Bool)
    case rentPaid(payerID: Player.ID, ownerID: Player.ID, amount: Int, tileID: Int)
    case taxPaid(playerID: Player.ID, amount: Int, tileID: Int)
    case cardDrawn(playerID: Player.ID, deck: CardDeckKind, effect: CardEffect)
    case cashChanged(playerID: Player.ID, delta: Int, reason: String)
    case tilePurchased(playerID: Player.ID, tileID: Int, price: Int)
    case houseBuilt(playerID: Player.ID, tileID: Int, newLevel: Int)
    case sentToJail(playerID: Player.ID)
    case releasedFromJail(playerID: Player.ID, method: JailReleaseMethod)
    case playerBankrupted(playerID: Player.ID, toCreditorID: Player.ID?)
    case gameOver(winnerID: Player.ID?)
    case turnEnded(nextPlayerID: Player.ID)
}

public enum JailReleaseMethod: Codable, Equatable, Sendable {
    case rolledDoubles
    case paidFine(Int)
    case usedCard
    case servedSentence
}
