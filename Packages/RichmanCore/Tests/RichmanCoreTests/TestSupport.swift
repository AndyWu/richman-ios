@testable import RichmanCore

/// A small, fully-controlled 10-tile board used across engine tests so
/// scenarios (rent, bankruptcy, jail, cards) don't depend on the exact
/// shape of `StandardBoard`.
///
///  0 Go              5 Jail
///  1 Property A      6 Transit
///  2 Property B      7 Community Chest
///  3 Chance          8 Utility
///  4 Tax (75)        9 Go To Jail
enum TestBoard {
    static func make() -> Board {
        Board(tiles: [
            Tile(id: 0, name: "Go", category: .go),
            Tile(id: 1, name: "Property A", category: .property(PropertyDetails(
                colorGroup: "Test", price: 100, rentTable: [10, 50, 150, 300, 400, 500], houseCost: 50
            ))),
            Tile(id: 2, name: "Property B", category: .property(PropertyDetails(
                colorGroup: "Test", price: 120, rentTable: [12, 60, 180, 360, 480, 600], houseCost: 60
            ))),
            Tile(id: 3, name: "Chance", category: .chance),
            Tile(id: 4, name: "Tax", category: .tax(amount: 75)),
            Tile(id: 5, name: "Jail", category: .jail),
            Tile(id: 6, name: "Transit", category: .transit(TransitDetails(price: 200))),
            Tile(id: 7, name: "Community Chest", category: .communityChest),
            Tile(id: 8, name: "Utility", category: .utility(UtilityDetails(price: 150))),
            Tile(id: 9, name: "Go To Jail", category: .goToJail)
        ])
    }
}
