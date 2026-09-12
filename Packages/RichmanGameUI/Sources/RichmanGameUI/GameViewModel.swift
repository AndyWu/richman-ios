import Foundation
import SwiftUI
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
    /// Non-nil while a roll's movement is being animated — the moving
    /// player's real `position` (already updated by the engine) is hidden
    /// behind this until the token visually finishes hopping there.
    @Published public private(set) var animatingPlayerID: Player.ID?
    @Published public private(set) var animatedPosition: Int?
    /// The tile the board should be zoomed in on (level 1), or `nil` for the
    /// whole-board overview (level 0). Set by `rollDice()` for the duration
    /// of the move; `nil` the rest of the time.
    @Published public private(set) var cameraFocusTileID: Int?

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
    public var isAnimatingMove: Bool { animatingPlayerID != nil }

    /// `state.players`, except the currently-animating player's position is
    /// replaced with wherever the hop animation has visually gotten to.
    /// `BoardView` should render this instead of `state.players` directly.
    public var displayPlayers: [Player] {
        guard let state else { return [] }
        guard let animatingPlayerID, let animatedPosition else { return state.players }
        return state.players.map { player in
            guard player.id == animatingPlayerID else { return player }
            var moved = player
            moved.position = animatedPosition
            return moved
        }
    }

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

    /// Abandons the current game (if any) and returns to the city picker —
    /// `GameRootView` shows it whenever `board`/`engine` are `nil`.
    public func restartToCityPicker() {
        objectWillChange.send()
        board = nil
        engine = nil
        eventLog = []
        pendingPurchaseTileID = nil
        lastRoll = nil
        animatingPlayerID = nil
        animatedPosition = nil
        cameraFocusTileID = nil
        cityLoadMessage = nil
    }

    // MARK: - Turn actions

    /// Rolls, applies the turn, then animates the token hopping tile-by-tile
    /// from where it started to wherever the dice roll landed it — zooming
    /// the board in for the move and back out to the overview once it's
    /// done. `pendingPurchaseTileID` (which drives the buy/skip prompt) is
    /// only published once the animation finishes, so the prompt doesn't
    /// appear before the token visually arrives.
    ///
    /// `hopStepDuration`/`zoomSettleDuration` default to a medium pace;
    /// callers pass the user's chosen `AnimationSpeed` durations (or `0` in
    /// tests, so this settles immediately instead of waiting in real time).
    public func rollDice(hopStepDuration: TimeInterval = 0.22, zoomSettleDuration: TimeInterval = 0.35) async {
        guard let engine, animatingPlayerID == nil else { return }
        let playerIndex = engine.state.currentPlayerIndex
        let playerID = engine.state.players[playerIndex].id
        let startPosition = engine.state.players[playerIndex].position
        let tileCount = engine.state.board.tileCount

        objectWillChange.send()
        let events = engine.takeTurn()
        for event in events {
            if case .diceRolled(_, let roll) = event { lastRoll = roll }
            eventLog.append(describe(event))
        }

        let primaryMove = events.first { event -> Bool in
            if case .playerMoved(let movedPlayerID, _, _, _) = event { return movedPlayerID == playerID }
            return false
        }
        guard case .some(.playerMoved(_, _, let destination, _)) = primaryMove else {
            // No movement this roll (e.g. still in jail) — nothing to animate.
            pendingPurchaseTileID = engine.pendingPurchaseTileID
            return
        }

        await animateHop(
            playerID: playerID, from: startPosition, to: destination, tileCount: tileCount,
            hopStepDuration: hopStepDuration, zoomSettleDuration: zoomSettleDuration
        )
        pendingPurchaseTileID = engine.pendingPurchaseTileID
    }

    private func animateHop(
        playerID: Player.ID, from: Int, to: Int, tileCount: Int,
        hopStepDuration: TimeInterval, zoomSettleDuration: TimeInterval
    ) async {
        let path = Self.hopPath(from: from, to: to, tileCount: tileCount)
        guard !path.isEmpty else { return }

        animatingPlayerID = playerID
        animatedPosition = from

        for tile in path {
            withAnimation(.easeInOut(duration: hopStepDuration)) {
                animatedPosition = tile
                cameraFocusTileID = tile
            }
            if hopStepDuration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(hopStepDuration * 1_000_000_000))
            }
        }

        withAnimation(.easeInOut(duration: zoomSettleDuration)) {
            cameraFocusTileID = nil
        }
        if zoomSettleDuration > 0 {
            try? await Task.sleep(nanoseconds: UInt64(zoomSettleDuration * 1_000_000_000))
        }

        animatingPlayerID = nil
        animatedPosition = nil
    }

    /// The sequence of tiles a token visually hops through moving forward
    /// from `from` to `to` (wrapping past the last tile back to 0), one at a
    /// time. `internal` (not private) so tests can verify it directly.
    static func hopPath(from: Int, to: Int, tileCount: Int) -> [Int] {
        guard tileCount > 0 else { return [] }
        guard from != to else { return [to] }
        var path: [Int] = []
        var current = from
        while current != to {
            current = (current + 1) % tileCount
            path.append(current)
        }
        return path
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
