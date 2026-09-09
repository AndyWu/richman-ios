/// A generic, non-city-specific board built from `BoardTemplate.classicSlotOrder`.
/// Used for tests, previews, and as the fallback when no real-city
/// `CityBoardLayout` is available yet. `RichmanCityData` builds the real-world
/// version players actually see, using the same template and pricing.
public enum StandardBoard {
    private static let groupNames = [
        "Brownstone Row", "Seaside Avenue", "Rose Garden", "Sunset Boulevard",
        "Crimson Court", "Golden Plaza", "Emerald Terrace", "Sapphire Heights"
    ]

    public static func classic40Tile() -> Board {
        let tiles: [Tile] = BoardTemplate.classicSlotOrder.enumerated().map { position, slot in
            Tile(id: position, name: name(for: slot, position: position), category: category(for: slot))
        }
        return Board(tiles: tiles)
    }

    private static func name(for slot: BoardSlotKind, position: Int) -> String {
        switch slot {
        case .go: return "Go"
        case .jail: return "Jail"
        case .freeParking: return "Free Parking"
        case .goToJail: return "Go To Jail"
        case .tax(let amount): return amount >= 200 ? "Income Tax" : "Luxury Tax"
        case .chance: return "Chance"
        case .communityChest: return "Community Chest"
        case .transit: return "Transit Station \((position / 10) + 1)"
        case .utility: return position < 20 ? "Electric Company" : "Water Works"
        case .property(let group, let indexInGroup):
            return "\(groupNames[group]) \(indexInGroup + 1)"
        }
    }

    private static func category(for slot: BoardSlotKind) -> TileCategory {
        switch slot {
        case .go: return .go
        case .jail: return .jail
        case .freeParking: return .freeParking
        case .goToJail: return .goToJail
        case .tax(let amount): return .tax(amount: amount)
        case .chance: return .chance
        case .communityChest: return .communityChest
        case .transit: return .transit(BoardTemplate.transitDetails())
        case .utility: return .utility(BoardTemplate.utilityDetails())
        case .property(let group, let indexInGroup):
            return .property(BoardTemplate.propertyDetails(colorGroupName: groupNames[group], group: group, indexInGroup: indexInGroup))
        }
    }
}
