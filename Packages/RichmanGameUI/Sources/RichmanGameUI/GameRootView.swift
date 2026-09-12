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
    @StateObject private var settings = SettingsStore()
    @State private var isShowingSettings = false

    public init(cityDataProvider: CityDataProvider, assetProvider: AssetProvider = PlaceholderAssetProvider()) {
        _viewModel = StateObject(wrappedValue: GameViewModel(cityDataProvider: cityDataProvider, assetProvider: assetProvider))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Its own row (not an overlay) so it never sits on top of the
            // turn control bar's own trailing button ("End Turn") when a
            // game is in progress.
            HStack {
                Spacer()
                settingsButton
            }

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
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings, isGameInProgress: viewModel.state != nil) {
                viewModel.restartToCityPicker()
            }
        }
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .padding(.trailing, 12)
        .padding(.top, 4)
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private func gameView(state: GameState, board: Board) -> some View {
        VStack(spacing: 12) {
            turnControlBar(state: state)

            BoardView(
                board: board,
                tileStates: state.tileStates,
                players: viewModel.displayPlayers,
                assetProvider: viewModel.assetProvider,
                cameraFocusTileID: viewModel.cameraFocusTileID
            )

            PlayerHUDView(players: state.players, currentPlayerIndex: state.currentPlayerIndex, assetProvider: viewModel.assetProvider)
                .padding(.horizontal)

            eventLogView

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Turn/dice/roll controls, rendered above the board rather than
    /// floating over it — on a geo (real-city) board the board's middle is
    /// full of routes and tiles, not empty space, so overlaying controls
    /// there hid part of the map. When a purchase is pending, this bar
    /// swaps to the buy/skip prompt instead of stacking a second floating
    /// dialog on top of the board (which had the same problem).
    @ViewBuilder
    private func turnControlBar(state: GameState) -> some View {
        Group {
            if let tileID = viewModel.pendingPurchaseTileID, let price = viewModel.pendingPurchasePrice {
                purchasePrompt(tile: state.board.tile(at: tileID), price: price, playerCash: state.currentPlayer.cash)
            } else {
                turnControls(state: state)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func turnControls(state: GameState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isGameOver ? "Game Over" : "\(state.currentPlayer.name)'s turn")
                    .font(.headline)
                if !state.isGameOver, state.currentPlayer.isInJail {
                    Button("Pay $50 to leave jail") { viewModel.payToLeaveJail() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }

            Spacer(minLength: 8)

            DiceView(roll: viewModel.lastRoll, assetProvider: viewModel.assetProvider)

            if !state.isGameOver {
                Button("Roll Dice") {
                    Task {
                        await viewModel.rollDice(
                            hopStepDuration: settings.animationSpeed.hopStepDuration,
                            zoomSettleDuration: settings.animationSpeed.zoomSettleDuration
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.hasRolledThisTurn)

                Button("End Turn") { viewModel.endTurn() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAnimatingMove)
            }
        }
    }

    @ViewBuilder
    private func purchasePrompt(tile: Tile, price: Int, playerCash: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name)
                    .font(.headline)
                Text("$\(price)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Skip", role: .cancel) { viewModel.declinePendingTile() }
            Button("Buy") { viewModel.buyPendingTile() }
                .buttonStyle(.borderedProminent)
                .disabled(playerCash < price)
        }
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
