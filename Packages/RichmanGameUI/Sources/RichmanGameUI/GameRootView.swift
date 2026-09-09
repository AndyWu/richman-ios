import SwiftUI
import RichmanCore
import RichmanCityData
import RichmanAssetsKit

/// The one view `RichmanApp` needs to show. Everything else in this package
/// is an implementation detail. Owns the `GameViewModel`; `cityDataProvider`
/// is injected so the app target decides whether that's the live OSM
/// provider, a caching wrapper, or a mock (see `Docs/ARCHITECTURE.md`).
public struct GameRootView: View {
    @StateObject private var viewModel: GameViewModel

    public init(cityDataProvider: CityDataProvider, assetProvider: AssetProvider = PlaceholderAssetProvider()) {
        _viewModel = StateObject(wrappedValue: GameViewModel(cityDataProvider: cityDataProvider, assetProvider: assetProvider))
    }

    public var body: some View {
        Group {
            if let state = viewModel.state, let board = viewModel.board {
                gameView(state: state, board: board)
            } else {
                CityPickerView(isLoading: viewModel.isLoadingCity, message: viewModel.cityLoadMessage) { city, names in
                    Task { await viewModel.startGame(cityName: city, playerNames: names) }
                }
            }
        }
    }

    @ViewBuilder
    private func gameView(state: GameState, board: Board) -> some View {
        VStack(spacing: 12) {
            BoardView(
                board: board,
                tileStates: state.tileStates,
                players: state.players,
                assetProvider: viewModel.assetProvider
            ) {
                centerContent(state: state)
            }

            PlayerHUDView(players: state.players, currentPlayerIndex: state.currentPlayerIndex, assetProvider: viewModel.assetProvider)
                .padding(.horizontal)

            eventLogView

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if let tileID = viewModel.pendingPurchaseTileID, let price = viewModel.pendingPurchasePrice {
                PropertyDialogView(
                    tile: board.tile(at: tileID),
                    price: price,
                    playerCash: state.currentPlayer.cash,
                    onBuy: { viewModel.buyPendingTile() },
                    onDecline: { viewModel.declinePendingTile() }
                )
            }
        }
    }

    @ViewBuilder
    private func centerContent(state: GameState) -> some View {
        VStack(spacing: 10) {
            Text(state.isGameOver ? "Game Over" : "\(state.currentPlayer.name)'s turn")
                .font(.headline)
                .multilineTextAlignment(.center)

            DiceView(roll: viewModel.lastRoll, assetProvider: viewModel.assetProvider)

            if !state.isGameOver {
                if state.currentPlayer.isInJail {
                    Button("Pay $50 to leave jail") { viewModel.payToLeaveJail() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }

                Button("Roll Dice") { viewModel.rollDice() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.pendingPurchaseTileID != nil)

                Button("End Turn") { viewModel.endTurn() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.pendingPurchaseTileID != nil)
            }
        }
        .padding(8)
    }

    private var eventLogView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(viewModel.eventLog.suffix(6).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 80)
    }
}
