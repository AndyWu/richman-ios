import Foundation
import RichmanCore
import RichmanCityData
import RichmanAssetsKit

/// Drives a `GameEngine` for `RichmanGameUI`'s views. `GameEngine` is a
/// reference type that mutates itself in place, so this view model calls
/// `objectWillChange.send()` around every action rather than relying on
/// `@Published` (which only fires on assignment, not on a class's internal
/// mutation) — see `Docs/ARCHITECTURE.md`.
@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var board: Board?
    @Published public private(set) var isLoadingCity = false
    @Published public private(set) var cityLoadMessage: String?
    @Published public private(set) var eventLog: [String] = []
    @Published public private(set) var pendingPurchaseTileID: Int?
    @Published public private(set) var lastRoll: DiceRoll?

    public private(set) var engine: GameEngine?
    public let assetProvider: AssetProvider
    private let cityDataProvider: CityDataProvider
    private let makeDiceRoller: () -> DiceRoller

    /// `makeDiceRoller` defaults to the real `SystemDiceRoller`; tests pass a
    /// `ScriptedDiceRoller` factory to drive the engine deterministically.
    public init(
        cityDataProvider: CityDataProvider,
        assetProvider: AssetProvider = PlaceholderAssetProvider(),
        makeDiceRoller: @escaping () -> DiceRoller = { SystemDiceRoller() }
    ) {
        self.cityDataProvider = cityDataProvider
        self.assetProvider = assetProvider
        self.makeDiceRoller = makeDiceRoller
    }

    public var state: GameState? { engine?.state }
    public var pendingPurchasePrice: Int? { engine?.pendingPurchasePrice }
    public var hasRolledThisTurn: Bool { engine?.hasRolledThisTurn ?? false }

    // MARK: - Setup

    public func startGame(cityName: String?, playerNames: [String]) async {
        isLoadingCity = true
        cityLoadMessage = nil
        defer { isLoadingCity = false }

        let resolvedBoard: Board
        let trimmedCity = cityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCity.isEmpty {
            do {
                let layout = try await cityDataProvider.fetchBoardLayout(for: trimmedCity)
                resolvedBoard = layout.board
                cityLoadMessage = "Playing in \(layout.resolvedDisplayName)"
            } catch {
                resolvedBoard = StandardBoard.classic40Tile()
                cityLoadMessage = "Couldn't load \"\(trimmedCity)\" (\(Self.describe(error))) — using a generic board instead."
            }
        } else {
            resolvedBoard = StandardBoard.classic40Tile()
        }

        board = resolvedBoard
        let names = playerNames.isEmpty ? ["Player 1", "Player 2"] : playerNames
        engine = GameEngine(state: GameState.newGame(board: resolvedBoard, playerNames: names), diceRoller: makeDiceRoller())
        eventLog = []
        pendingPurchaseTileID = nil
    }

    // MARK: - Turn actions

    public func rollDice() {
        mutate { engine in engine.takeTurn() }
    }

    public func buyPendingTile() {
        mutate { engine in engine.purchasePendingTile() }
    }

    public func declinePendingTile() {
        objectWillChange.send()
        engine?.declinePendingTile()
        pendingPurchaseTileID = engine?.pendingPurchaseTileID
    }

    public func endTurn() {
        mutate { engine in engine.endTurn() }
    }

    public func payToLeaveJail() {
        mutate { engine in engine.payToLeaveJail() }
    }

    public func useGetOutOfJailFreeCard() {
        objectWillChange.send()
        _ = engine?.useGetOutOfJailFreeCard()
    }

    public func buildHouse(atTileID tileID: Int) {
        mutate { engine in engine.buildHouse(atTileID: tileID) }
    }

    private func mutate(_ action: (GameEngine) -> [GameEvent]) {
        guard let engine else { return }
        objectWillChange.send()
        let events = action(engine)
        for event in events {
            if case .diceRolled(_, let roll) = event { lastRoll = roll }
            eventLog.append(describe(event))
        }
        pendingPurchaseTileID = engine.pendingPurchaseTileID
    }

    // MARK: - Human-readable log

    private func describe(_ event: GameEvent) -> String {
        guard let state = engine?.state else { return "" }
        func name(_ id: Player.ID) -> String { state.player(withID: id)?.name ?? "Someone" }
        func tile(_ id: Int) -> String { state.board.tile(at: id).name }

        switch event {
        case .diceRolled(let playerID, let roll):
            return "\(name(playerID)) rolled \(roll.die1) + \(roll.die2) = \(roll.total)"
        case .playerMoved(let playerID, _, let to, let passedGo):
            return "\(name(playerID)) moved to \(tile(to))" + (passedGo ? " (passed Go, +$200)" : "")
        case .rentPaid(let payerID, let ownerID, let amount, let tileID):
            return "\(name(payerID)) paid $\(amount) rent to \(name(ownerID)) for \(tile(tileID))"
        case .taxPaid(let playerID, let amount, let tileID):
            return "\(name(playerID)) paid $\(amount) \(tile(tileID))"
        case .cardDrawn(let playerID, let deck, _):
            return "\(name(playerID)) drew a \(deck == .chance ? "Chance" : "Community Chest") card"
        case .cashChanged(let playerID, let delta, let reason):
            return "\(name(playerID)) \(delta >= 0 ? "gained" : "lost") $\(abs(delta)) (\(reason))"
        case .tilePurchased(let playerID, let tileID, let price):
            return "\(name(playerID)) bought \(tile(tileID)) for $\(price)"
        case .houseBuilt(let playerID, let tileID, let newLevel):
            return "\(name(playerID)) built on \(tile(tileID)) (level \(newLevel))"
        case .sentToJail(let playerID):
            return "\(name(playerID)) was sent to jail"
        case .releasedFromJail(let playerID, let method):
            return "\(name(playerID)) left jail (\(Self.describe(method)))"
        case .playerBankrupted(let playerID, let creditorID):
            return "\(name(playerID)) went bankrupt" + (creditorID.map { " to \(name($0))" } ?? "")
        case .gameOver(let winnerID):
            return winnerID.map { "\(name($0)) wins!" } ?? "Game over"
        case .turnEnded(let nextPlayerID):
            return "\(name(nextPlayerID))'s turn"
        }
    }

    private static func describe(_ method: JailReleaseMethod) -> String {
        switch method {
        case .rolledDoubles: return "rolled doubles"
        case .paidFine(let amount): return "paid $\(amount)"
        case .usedCard: return "used a card"
        case .servedSentence: return "served the sentence"
        }
    }

    private static func describe(_ error: Error) -> String {
        if let cityError = error as? CityDataError {
            switch cityError {
            case .cityNotFound: return "city not found"
            case .insufficientData: return "not enough map data"
            case .network: return "network error"
            case .invalidResponse: return "bad response"
            }
        }
        return error.localizedDescription
    }
}
