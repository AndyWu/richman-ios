/// A fixed-size, ordered sequence of tiles a player's token moves around.
/// Position `0` is always Go; positions increase clockwise.
public struct Board: Codable, Equatable, Sendable {
    public var tiles: [Tile]

    public init(tiles: [Tile]) {
        precondition(!tiles.isEmpty, "Board must have at least one tile")
        self.tiles = tiles
    }

    public var tileCount: Int { tiles.count }

    public func tile(at position: Int) -> Tile {
        tiles[position % tiles.count]
    }

    /// All tile indices belonging to the same color group as `colorGroup`, in board order.
    public func propertyIndices(inColorGroup colorGroup: String) -> [Int] {
        tiles.indices.filter {
            if case .property(let details) = tiles[$0].category {
                return details.colorGroup == colorGroup
            }
            return false
        }
    }

    /// All tile indices that are transit tiles (e.g. train/subway stations).
    public var transitIndices: [Int] {
        tiles.indices.filter {
            if case .transit = tiles[$0].category { return true }
            return false
        }
    }

    /// All tile indices that are utility tiles.
    public var utilityIndices: [Int] {
        tiles.indices.filter {
            if case .utility = tiles[$0].category { return true }
            return false
        }
    }
}

public struct Tile: Identifiable, Codable, Equatable, Sendable {
    /// The tile's fixed board position; also its stable identity.
    public var id: Int
    public var name: String
    public var category: TileCategory
    /// A rendering hint only — never read by `GameEngine`/`GameState`. Real-city
    /// boards (`RichmanCityData`) set this so `RichmanGameUI` can lay the board
    /// out as a path tracing the city's real shape instead of a square; `nil`
    /// (the case for `StandardBoard`) means "no real geography, use the
    /// classic square layout."
    public var mapPosition: TileMapPosition?

    public init(id: Int, name: String, category: TileCategory, mapPosition: TileMapPosition? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.mapPosition = mapPosition
    }

    public var isOwnable: Bool {
        switch category {
        case .property, .transit, .utility: return true
        default: return false
        }
    }
}

/// A tile's position for path-based (real-geography) board rendering,
/// normalized to 0...1 on both axes with the real city's aspect ratio
/// preserved. `y` increases downward (screen convention).
public struct TileMapPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum TileCategory: Codable, Equatable, Sendable {
    case go
    case property(PropertyDetails)
    case transit(TransitDetails)
    case utility(UtilityDetails)
    case chance
    case communityChest
    case tax(amount: Int)
    case jail
    case goToJail
    case freeParking
}

public struct PropertyDetails: Codable, Equatable, Sendable {
    public var colorGroup: String
    public var price: Int
    /// Rent with 0, 1, 2, 3, 4 houses, then a hotel — always 6 entries.
    public var rentTable: [Int]
    public var houseCost: Int

    public init(colorGroup: String, price: Int, rentTable: [Int], houseCost: Int) {
        precondition(rentTable.count == 6, "rentTable must have 6 entries: base, 1-4 houses, hotel")
        self.colorGroup = colorGroup
        self.price = price
        self.rentTable = rentTable
        self.houseCost = houseCost
    }

    public func rent(atBuildingLevel level: Int) -> Int {
        rentTable[max(0, min(level, rentTable.count - 1))]
    }
}

public struct TransitDetails: Codable, Equatable, Sendable {
    public var price: Int
    /// Rent when the owner holds 1, 2, 3, 4 transit tiles — always 4 entries.
    public var rentByOwnedCount: [Int]

    public init(price: Int, rentByOwnedCount: [Int] = [25, 50, 100, 200]) {
        self.price = price
        self.rentByOwnedCount = rentByOwnedCount
    }

    public func rent(forOwnedCount count: Int) -> Int {
        rentByOwnedCount[max(1, min(count, rentByOwnedCount.count)) - 1]
    }
}

public struct UtilityDetails: Codable, Equatable, Sendable {
    public var price: Int
    /// Dice-roll multiplier when the owner holds 1 vs. both utilities.
    public var rentMultiplierByOwnedCount: [Int]

    public init(price: Int, rentMultiplierByOwnedCount: [Int] = [4, 10]) {
        self.price = price
        self.rentMultiplierByOwnedCount = rentMultiplierByOwnedCount
    }

    public func rentMultiplier(forOwnedCount count: Int) -> Int {
        rentMultiplierByOwnedCount[max(1, min(count, rentMultiplierByOwnedCount.count)) - 1]
    }
}
