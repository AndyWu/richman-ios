/// The fixed 40-slot *shape* every Richman board uses, independent of theme:
/// which positions are properties (and which color group/index within it),
/// which are transit, utility, tax, chance, community chest, or corners.
///
/// `StandardBoard` fills this shape with generic placeholder content.
/// `RichmanCityData` fills the same shape with a real city's streets,
/// stations, and landmarks. Sharing one template means both always agree on
/// board geometry (property counts per group, corner positions, etc) — a
/// city board is never structurally different from the generic one, only
/// re-skinned.
public enum BoardSlotKind: Equatable, Sendable {
    case go, jail, freeParking, goToJail
    case tax(Int)
    case chance, communityChest
    case transit
    case utility
    case property(group: Int, indexInGroup: Int)
}

public enum BoardTemplate {
    /// 8 color groups, sized 2, 3, 3, 3, 3, 3, 3, 2 (22 properties total) —
    /// the same shape as the classic 40-tile Monopoly-style board.
    public static let colorGroupSizes = [2, 3, 3, 3, 3, 3, 3, 2]

    /// Total number of property tiles (sum of `colorGroupSizes`).
    public static let propertyCount = colorGroupSizes.reduce(0, +)
    public static let transitCount = 4
    public static let utilityCount = 2

    private static let groupBasePrices = [60, 100, 140, 180, 220, 260, 300, 350]
    private static let groupPriceStep = [20, 20, 20, 20, 20, 20, 20, 50]

    /// The shared price/rent formula every board (generic or city-themed)
    /// uses, so a group-7 property always costs and rents the same regardless
    /// of whether it's called "Sapphire Heights" or "5th Avenue".
    public static func propertyDetails(colorGroupName: String, group: Int, indexInGroup: Int) -> PropertyDetails {
        let base = groupBasePrices[group] + groupPriceStep[group] * indexInGroup
        let rentBase = base / 10
        return PropertyDetails(
            colorGroup: colorGroupName,
            price: base,
            rentTable: [rentBase, rentBase * 5, rentBase * 15, rentBase * 30, rentBase * 40, rentBase * 50],
            houseCost: base / 2
        )
    }

    public static func transitDetails() -> TransitDetails { TransitDetails(price: 200) }
    public static func utilityDetails() -> UtilityDetails { UtilityDetails(price: 150) }

    public static let classicSlotOrder: [BoardSlotKind] = [
        .go,
        .property(group: 0, indexInGroup: 0),
        .communityChest,
        .property(group: 0, indexInGroup: 1),
        .tax(200),
        .transit,
        .property(group: 1, indexInGroup: 0),
        .chance,
        .property(group: 1, indexInGroup: 1),
        .property(group: 1, indexInGroup: 2),
        .jail,
        .property(group: 2, indexInGroup: 0),
        .utility,
        .property(group: 2, indexInGroup: 1),
        .property(group: 2, indexInGroup: 2),
        .transit,
        .property(group: 3, indexInGroup: 0),
        .communityChest,
        .property(group: 3, indexInGroup: 1),
        .property(group: 3, indexInGroup: 2),
        .freeParking,
        .property(group: 4, indexInGroup: 0),
        .chance,
        .property(group: 4, indexInGroup: 1),
        .property(group: 4, indexInGroup: 2),
        .transit,
        .property(group: 5, indexInGroup: 0),
        .property(group: 5, indexInGroup: 1),
        .utility,
        .property(group: 5, indexInGroup: 2),
        .goToJail,
        .property(group: 6, indexInGroup: 0),
        .property(group: 6, indexInGroup: 1),
        .communityChest,
        .property(group: 6, indexInGroup: 2),
        .transit,
        .chance,
        .property(group: 7, indexInGroup: 0),
        .tax(100),
        .property(group: 7, indexInGroup: 1)
    ]
}
