import Foundation

public struct GameState: Codable, Equatable, Sendable {
    public var board: Board
    public var players: [Player]
    /// Parallel to `board.tiles`, indexed the same way.
    public var tileStates: [TileState]
    public var currentPlayerIndex: Int
    public var chanceDeck: CardDeck
    public var communityChestDeck: CardDeck
    public var isGameOver: Bool

    public init(
        board: Board,
        players: [Player],
        chanceDeck: CardDeck,
        communityChestDeck: CardDeck,
        currentPlayerIndex: Int = 0,
        isGameOver: Bool = false
    ) {
        precondition(players.count >= 2, "Richman needs at least 2 players")
        self.board = board
        self.players = players
        self.tileStates = board.tiles.map { _ in TileState() }
        self.currentPlayerIndex = currentPlayerIndex
        self.chanceDeck = chanceDeck
        self.communityChestDeck = communityChestDeck
        self.isGameOver = isGameOver
    }

    public var currentPlayer: Player { players[currentPlayerIndex] }

    public func player(withID id: Player.ID) -> Player? {
        players.first { $0.id == id }
    }

    public func indexOfPlayer(withID id: Player.ID) -> Int? {
        players.firstIndex { $0.id == id }
    }

    public var activePlayers: [Player] {
        players.filter { !$0.isBankrupt }
    }

    /// Convenience factory: a standard 2-4 player game on the given board,
    /// starting at Go with freshly shuffled decks. Starting cash is 10x the
    /// board's most expensive property, so it scales with whatever board is
    /// in play (a generic board and a real-city board can have different
    /// price ranges) rather than being a fixed dollar amount.
    public static func newGame(board: Board, playerNames: [String]) -> GameState {
        let cash = startingCash(for: board)
        let players = playerNames.map { Player(name: $0, cash: cash) }
        let goID = board.tiles.first { if case .go = $0.category { return true }; return false }?.id ?? 0
        let jailID = board.tiles.first { if case .jail = $0.category { return true }; return false }?.id ?? 0
        return GameState(
            board: board,
            players: players,
            chanceDeck: CardDeck(cards: CardDeck.standard(goTileID: goID, jailTileID: jailID).shuffled()),
            communityChestDeck: CardDeck(cards: CardDeck.standard(goTileID: goID, jailTileID: jailID).shuffled())
        )
    }

    private static func startingCash(for board: Board) -> Int {
        let mostExpensiveProperty = board.tiles.compactMap { tile -> Int? in
            if case .property(let details) = tile.category { return details.price }
            return nil
        }.max() ?? 150
        return mostExpensiveProperty * 10
    }
}
