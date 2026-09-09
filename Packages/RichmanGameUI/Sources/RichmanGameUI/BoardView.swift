import SwiftUI
import RichmanCore
import RichmanAssetsKit

/// Renders the board two ways depending on what it's carrying:
/// - **Square mode** (`StandardBoard`, no real geography): the classic
///   Monopoly-style square perimeter, via `BoardLayoutMath`.
/// - **Geo mode** (a real-city board — every tile has a `mapPosition`): a
///   winding path whose overall shape traces the city's real geography,
///   tiles strung along it in board order.
///
/// Purely a renderer — all game logic lives in `GameEngine`/`GameViewModel`;
/// this view just draws `board`/`tileStates`/`players` and reports taps via
/// `onTileTapped`. `centerContent` fills the open middle of the board (dice,
/// current-turn info, roll button — supplied by the caller so this view
/// stays reusable).
public struct BoardView<CenterContent: View>: View {
    let board: Board
    let tileStates: [TileState]
    let players: [Player]
    let assetProvider: AssetProvider
    let onTileTapped: (Int) -> Void
    let centerContent: () -> CenterContent

    private let geoTileSize: CGFloat = 38

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

    private var isGeoBoard: Bool {
        board.tiles.allSatisfy { $0.mapPosition != nil }
    }

    public var body: some View {
        if isGeoBoard {
            geoBody
        } else {
            squareBody
        }
    }

    // MARK: - Square mode

    private var squareBody: some View {
        // `Color.clear.aspectRatio(1, contentMode: .fit)` is the size driver:
        // it reliably reports "as large as possible while staying square" to
        // the parent VStack. Chaining `.aspectRatio` directly after a
        // GeometryReader is a known-unreliable combination — GeometryReader
        // has no natural ideal size, so the parent often still allocates it
        // far more height than a square needs, leaving dead space.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    let cell = side / CGFloat(BoardLayoutMath.gridSize)

                    ZStack(alignment: .topLeading) {
                        ForEach(board.tiles) { tile in
                            squareTileView(for: tile, cell: cell)
                        }
                        ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                            squareTokenView(for: player, index: index, cell: cell)
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
            }
    }

    private func squareTileView(for tile: Tile, cell: CGFloat) -> some View {
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

    private func squareTokenView(for player: Player, index: Int, cell: CGFloat) -> some View {
        let position = BoardLayoutMath.gridPosition(forTileIndex: player.position)
        // Spread up to 4 tokens within a tile so they don't fully overlap.
        let jitter = CGFloat(index % 4)
        let dx = 0.28 + 0.22 * (jitter.truncatingRemainder(dividingBy: 2))
        let dy = 0.28 + 0.22 * (jitter / 2).rounded(.down)
        return tokenCircle(index: index, isBankrupt: player.isBankrupt, diameter: cell * 0.3)
            .position(x: CGFloat(position.col) * cell + cell * dx, y: CGFloat(position.row) * cell + cell * dy)
    }

    // MARK: - Geo mode

    private var geoBody: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                pathShape(in: size)
                    .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                ForEach(board.tiles) { tile in
                    geoTileView(for: tile, in: size)
                }
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    geoTokenView(for: player, index: index, in: size)
                }
                centerContent()
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: size.width * 0.42)
                    .position(centroid(in: size))
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// The connecting "road": a closed loop through every tile's real
    /// position, in board order — the classic 大富翁-style path shape.
    private func pathShape(in size: CGSize) -> Path {
        var path = Path()
        let points = board.tiles.compactMap { tile -> CGPoint? in
            guard let position = tile.mapPosition else { return nil }
            return CGPoint(x: position.x * size.width, y: position.y * size.height)
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    private func geoTileView(for tile: Tile, in size: CGSize) -> some View {
        if let position = tile.mapPosition {
            TileView(
                tile: tile,
                tileState: tileStates[tile.id],
                ownerColor: ownerColor(forTileID: tile.id),
                assetProvider: assetProvider
            )
            .frame(width: geoTileSize, height: geoTileSize)
            .position(x: position.x * size.width, y: position.y * size.height)
            .contentShape(Rectangle())
            .onTapGesture { onTileTapped(tile.id) }
        }
    }

    @ViewBuilder
    private func geoTokenView(for player: Player, index: Int, in size: CGSize) -> some View {
        if let position = board.tile(at: player.position).mapPosition {
            let jitter = CGFloat(index % 4)
            let dx = (jitter.truncatingRemainder(dividingBy: 2) - 0.5) * geoTileSize * 0.6
            let dy = ((jitter / 2).rounded(.down) - 0.5) * geoTileSize * 0.6
            tokenCircle(index: index, isBankrupt: player.isBankrupt, diameter: geoTileSize * 0.32)
                .position(x: position.x * size.width + dx, y: position.y * size.height + dy)
        }
    }

    /// Average of every tile's real position — for an angle-sorted loop this
    /// naturally falls inside it, giving `centerContent` the same "middle of
    /// the loop" placement the square mode gets from simple geometry.
    private func centroid(in size: CGSize) -> CGPoint {
        let positions = board.tiles.compactMap(\.mapPosition)
        guard !positions.isEmpty else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let averageX = positions.map(\.x).reduce(0, +) / Double(positions.count)
        let averageY = positions.map(\.y).reduce(0, +) / Double(positions.count)
        return CGPoint(x: averageX * size.width, y: averageY * size.height)
    }

    // MARK: - Shared

    private func tokenCircle(index: Int, isBankrupt: Bool, diameter: CGFloat) -> some View {
        Circle()
            .fill(assetProvider.tokenColor(for: index))
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .frame(width: diameter, height: diameter)
            .opacity(isBankrupt ? 0.25 : 1)
            .allowsHitTesting(false)
    }

    private func ownerColor(forTileID tileID: Int) -> Color? {
        guard let ownerID = tileStates[tileID].ownerID,
              let index = players.firstIndex(where: { $0.id == ownerID })
        else { return nil }
        return assetProvider.tokenColor(for: index)
    }
}
