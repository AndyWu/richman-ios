import SwiftUI
import RichmanCore
import RichmanAssetsKit

/// The classic top-down, square-perimeter board. Purely a renderer — all
/// game logic lives in `GameEngine`/`GameViewModel`; this view just draws
/// `board`/`tileStates`/`players` and reports taps via `onTileTapped`.
/// `centerContent` fills the open middle of the board (dice, current-turn
/// info, roll button — supplied by the caller so this view stays reusable).
public struct BoardView<CenterContent: View>: View {
    let board: Board
    let tileStates: [TileState]
    let players: [Player]
    let assetProvider: AssetProvider
    let onTileTapped: (Int) -> Void
    let centerContent: () -> CenterContent

    public init(
        board: Board,
        tileStates: [TileState],
        players: [Player],
        assetProvider: AssetProvider,
        onTileTapped: @escaping (Int) -> Void = { _ in },
        @ViewBuilder centerContent: @escaping () -> CenterContent
    ) {
        self.board = board
        self.tileStates = tileStates
        self.players = players
        self.assetProvider = assetProvider
        self.onTileTapped = onTileTapped
        self.centerContent = centerContent
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / CGFloat(BoardLayoutMath.gridSize)

            ZStack(alignment: .topLeading) {
                ForEach(board.tiles) { tile in
                    tileView(for: tile, cell: cell)
                }
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    tokenView(for: player, index: index, cell: cell)
                }
                centerContent()
                    .frame(
                        width: cell * CGFloat(BoardLayoutMath.gridSize - 2),
                        height: cell * CGFloat(BoardLayoutMath.gridSize - 2)
                    )
                    .position(x: side / 2, y: side / 2)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func tileView(for tile: Tile, cell: CGFloat) -> some View {
        let position = BoardLayoutMath.gridPosition(forTileIndex: tile.id)
        return TileView(
            tile: tile,
            tileState: tileStates[tile.id],
            ownerColor: ownerColor(forTileID: tile.id),
            assetProvider: assetProvider
        )
        .frame(width: cell, height: cell)
        .position(x: CGFloat(position.col) * cell + cell / 2, y: CGFloat(position.row) * cell + cell / 2)
        .contentShape(Rectangle())
        .onTapGesture { onTileTapped(tile.id) }
    }

    private func tokenView(for player: Player, index: Int, cell: CGFloat) -> some View {
        let position = BoardLayoutMath.gridPosition(forTileIndex: player.position)
        // Spread up to 4 tokens within a tile so they don't fully overlap.
        let jitter = CGFloat(index % 4)
        let dx = 0.28 + 0.22 * (jitter.truncatingRemainder(dividingBy: 2))
        let dy = 0.28 + 0.22 * (jitter / 2).rounded(.down)
        return Circle()
            .fill(assetProvider.tokenColor(for: index))
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .frame(width: cell * 0.3, height: cell * 0.3)
            .position(x: CGFloat(position.col) * cell + cell * dx, y: CGFloat(position.row) * cell + cell * dy)
            .opacity(player.isBankrupt ? 0.25 : 1)
            .allowsHitTesting(false)
    }

    private func ownerColor(forTileID tileID: Int) -> Color? {
        guard let ownerID = tileStates[tileID].ownerID,
              let index = players.firstIndex(where: { $0.id == ownerID })
        else { return nil }
        return assetProvider.tokenColor(for: index)
    }
}
