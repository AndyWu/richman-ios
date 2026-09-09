import Foundation

public struct Player: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var cash: Int
    /// Board position, 0..<board.tileCount.
    public var position: Int
    public var isInJail: Bool
    public var jailTurnsRemaining: Int
    public var getOutOfJailFreeCards: Int
    public var isBankrupt: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        cash: Int = 1_500,
        position: Int = 0,
        isInJail: Bool = false,
        jailTurnsRemaining: Int = 0,
        getOutOfJailFreeCards: Int = 0,
        isBankrupt: Bool = false
    ) {
        self.id = id
        self.name = name
        self.cash = cash
        self.position = position
        self.isInJail = isInJail
        self.jailTurnsRemaining = jailTurnsRemaining
        self.getOutOfJailFreeCards = getOutOfJailFreeCards
        self.isBankrupt = isBankrupt
    }
}

/// Per-tile ownership/building state, kept separate from the static `Board`
/// so the same board template can back many independent games.
public struct TileState: Codable, Equatable, Sendable {
    public var ownerID: Player.ID?
    /// 0 = no buildings, 1-4 = houses, 5 = hotel. Only meaningful for `.property` tiles.
    public var buildingLevel: Int
    public var isMortgaged: Bool

    public init(ownerID: Player.ID? = nil, buildingLevel: Int = 0, isMortgaged: Bool = false) {
        self.ownerID = ownerID
        self.buildingLevel = buildingLevel
        self.isMortgaged = isMortgaged
    }
}
