public enum CardDeckKind: Codable, Equatable, Sendable {
    case chance
    case communityChest
}

/// A single Chance/Community-Chest style card effect. Named generically
/// (not "Chance"/"命運" strings) so `RichmanGameUI` supplies the localized,
/// flavorful card text — this type only carries the mechanical effect.
public enum CardEffect: Codable, Equatable, Sendable {
    case collect(Int)
    case pay(Int)
    case moveToTile(id: Int, collectGoIfPassed: Bool)
    case moveRelative(spaces: Int)
    case goToJail
    case getOutOfJailFree
    /// Pay an amount per house owned, and a larger amount per hotel owned.
    case repairs(perHouse: Int, perHotel: Int)
    case collectFromEachPlayer(Int)
    case payToEachPlayer(Int)
}

public struct CardDeck: Codable, Equatable, Sendable {
    private var faceDownCards: [CardEffect]
    private var discardPile: [CardEffect] = []

    public init(cards: [CardEffect]) {
        precondition(!cards.isEmpty, "CardDeck needs at least one card")
        self.faceDownCards = cards
    }

    /// Draws the top card, cycling it (and the discard pile) back in once exhausted.
    public mutating func draw() -> CardEffect {
        if faceDownCards.isEmpty {
            faceDownCards = discardPile
            discardPile = []
        }
        let card = faceDownCards.removeFirst()
        discardPile.append(card)
        return card
    }

    /// A standard, 大富翁/Monopoly-flavored deck of mechanical effects.
    /// `goTileID`/`jailTileID` let the deck target the actual board layout in use.
    public static func standard(goTileID: Int, jailTileID: Int) -> [CardEffect] {
        [
            .collect(200),
            .collect(50),
            .pay(100),
            .pay(50),
            .moveToTile(id: goTileID, collectGoIfPassed: false),
            .moveToTile(id: jailTileID, collectGoIfPassed: false),
            .goToJail,
            .getOutOfJailFree,
            .moveRelative(spaces: -3),
            .repairs(perHouse: 25, perHotel: 100),
            .collectFromEachPlayer(50),
            .payToEachPlayer(50)
        ]
    }
}
