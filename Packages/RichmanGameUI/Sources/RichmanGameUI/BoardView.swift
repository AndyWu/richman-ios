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
/// `onTileTapped`. Turn/dice controls used to float over the board's open
/// middle, but on a geo board that middle isn't empty — it's covered in
/// routes and tiles — so those controls now live outside this view entirely
/// (see `GameRootView`), leaving `BoardView` free to use its full frame for
/// the board itself.
public struct BoardView: View {
    let board: Board
    let tileStates: [TileState]
    let players: [Player]
    let assetProvider: AssetProvider
    let onTileTapped: (Int) -> Void
    /// `nil` (level 0) shows the whole board, as always. A tile ID (level 1)
    /// zooms in and pans so that tile is centered — the caller animates this
    /// with `withAnimation` around the state change, so the transform here
    /// just needs to be a pure, continuous function of the value.
    let cameraFocusTileID: Int?

    private let geoTileSize: CGFloat = 38
    private let routeThickness: CGFloat = 12
    private let zoomedInScale: CGFloat = 2.4

    public init(
        board: Board,
        tileStates: [TileState],
        players: [Player],
        assetProvider: AssetProvider,
        cameraFocusTileID: Int? = nil,
        onTileTapped: @escaping (Int) -> Void = { _ in }
    ) {
        self.board = board
        self.tileStates = tileStates
        self.players = players
        self.assetProvider = assetProvider
        self.cameraFocusTileID = cameraFocusTileID
        self.onTileTapped = onTileTapped
    }

    /// Scale and top-leading-anchored offset that zoom the canvas in on
    /// `focusPoint`, or the identity transform when there's no focus (level
    /// 0). Expressed this way (rather than toggling between two discrete
    /// view trees) so `withAnimation` at the call site can interpolate
    /// smoothly between "whole board" and "zoomed on this tile" — and,
    /// tile-to-tile, pan smoothly as the focus point changes.
    private func zoomTransform(canvasSize: CGSize, focusPoint: CGPoint?) -> (scale: CGFloat, offset: CGSize) {
        guard let focusPoint else { return (1, .zero) }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return (
            zoomedInScale,
            CGSize(width: center.x - focusPoint.x * zoomedInScale, height: center.y - focusPoint.y * zoomedInScale)
        )
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
                    let focusPoint: CGPoint? = cameraFocusTileID.map { tileID in
                        let position = BoardLayoutMath.gridPosition(forTileIndex: tileID)
                        return CGPoint(x: CGFloat(position.col) * cell + cell / 2, y: CGFloat(position.row) * cell + cell / 2)
                    }
                    let (scale, offset) = zoomTransform(canvasSize: CGSize(width: side, height: side), focusPoint: focusPoint)

                    ZStack(alignment: .topLeading) {
                        ForEach(board.tiles) { tile in
                            squareTileView(for: tile, cell: cell)
                        }
                        ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                            squareTokenView(for: player, index: index, cell: cell)
                        }
                    }
                    .frame(width: side, height: side)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(offset)
                    .frame(width: side, height: side, alignment: .topLeading)
                    .clipped()
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
            let points = geoPositions(in: size)
            let focusPoint: CGPoint? = cameraFocusTileID.flatMap { points.indices.contains($0) ? points[$0] : nil }
            let (scale, offset) = zoomTransform(canvasSize: size, focusPoint: focusPoint)

            ZStack(alignment: .topLeading) {
                ForEach(routeSegments(points: points)) { segment in
                    segment.path.stroke(
                        segment.color.opacity(0.55),
                        style: StrokeStyle(lineWidth: routeThickness, lineCap: .round, lineJoin: .round)
                    )
                    ForEach(Array(segment.stops.enumerated()), id: \.offset) { _, stop in
                        Circle()
                            .fill(segment.color)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            .frame(width: routeThickness * 0.7, height: routeThickness * 0.7)
                            .position(stop)
                            .allowsHitTesting(false)
                    }
                }
                ForEach(board.tiles) { tile in
                    geoTileView(for: tile, points: points)
                }
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    geoTokenView(for: player, index: index, points: points)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(offset)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// Every tile's real `mapPosition` scaled to `size`, then pushed apart
    /// so no two tile chips are closer than one full chip-width to each
    /// other (i.e. at least a chip's own width of clear gap between their
    /// edges). Real geography routinely puts two tiles' raw positions
    /// within a few points of each other (two stops on the same corner,
    /// say) — with tile chips rendered at a fixed `geoTileSize` that reads
    /// as a pile of overlapping labels, so this keeps each tile's
    /// *direction* from the others but enforces that minimum separation.
    /// Routes, tile chips and tokens all read from this same array so the
    /// road segments still connect to where the chips actually ended up.
    private func geoPositions(in size: CGSize) -> [CGPoint] {
        guard board.tiles.allSatisfy({ $0.mapPosition != nil }) else { return [] }
        let margin = geoTileSize / 2 + 6
        let usableWidth = max(size.width - margin * 2, 1)
        let usableHeight = max(size.height - margin * 2, 1)
        let raw = board.tiles.map { tile -> CGPoint in
            let position = tile.mapPosition!
            return CGPoint(x: margin + CGFloat(position.x) * usableWidth, y: margin + CGFloat(position.y) * usableHeight)
        }
        let bounds = CGRect(
            x: margin, y: margin,
            width: max(size.width - margin * 2, 0), height: max(size.height - margin * 2, 0)
        )
        // Center-to-center distance of 2x the chip size leaves a full
        // chip-width of clear edge-to-edge gap between any two chips.
        return RouteGeometry.declutteredPositions(raw, minDistance: geoTileSize * 2, bounds: bounds)
    }

    /// One drawable piece of "road" per tile — the leg leaving that tile and
    /// heading to the next one in board order (wrapping from the last tile
    /// back to Go), each its own color so the route reads as a network of
    /// distinct named streets (Tube-map style) rather than one long line.
    private struct RouteSegment: Identifiable {
        let id: Int
        let path: Path
        let color: Color
        let stops: [CGPoint]
    }

    private func routeSegments(points: [CGPoint]) -> [RouteSegment] {
        guard points.count == board.tiles.count else { return [] }

        return points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]

            var path = Path()
            path.move(to: start)
            for waypoint in RouteGeometry.octilinearWaypoints(from: start, to: end) {
                path.addLine(to: waypoint)
            }

            return RouteSegment(
                id: index,
                path: path,
                color: RouteGeometry.routeColor(forTileIndex: index),
                // About one tile-width of road between stops — with tiles
                // now spaced at least a full chip-width apart (see
                // `geoPositions`), this puts a stop on most legs instead of
                // reserving them for unusually long real-world gaps.
                stops: RouteGeometry.intermediateStops(from: start, to: end, spacing: geoTileSize * 1.1)
            )
        }
    }

    @ViewBuilder
    private func geoTileView(for tile: Tile, points: [CGPoint]) -> some View {
        if points.indices.contains(tile.id) {
            let point = points[tile.id]
            TileView(
                tile: tile,
                tileState: tileStates[tile.id],
                ownerColor: ownerColor(forTileID: tile.id),
                assetProvider: assetProvider
            )
            .frame(width: geoTileSize, height: geoTileSize)
            .position(point)
            .contentShape(Rectangle())
            .onTapGesture { onTileTapped(tile.id) }
        }
    }

    @ViewBuilder
    private func geoTokenView(for player: Player, index: Int, points: [CGPoint]) -> some View {
        if points.indices.contains(player.position) {
            let point = points[player.position]
            let jitter = CGFloat(index % 4)
            let dx = (jitter.truncatingRemainder(dividingBy: 2) - 0.5) * geoTileSize * 0.6
            let dy = ((jitter / 2).rounded(.down) - 0.5) * geoTileSize * 0.6
            tokenCircle(index: index, isBankrupt: player.isBankrupt, diameter: geoTileSize * 0.32)
                .position(x: point.x + dx, y: point.y + dy)
        }
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

/// Path schematization for the geo board: turns arbitrary real positions
/// into Tube-map-clean segments. `internal` (not nested in `BoardView`) so
/// `RichmanGameUITests` can verify `octilinearWaypoints` directly without a
/// generic type parameter.
enum RouteGeometry {
    /// Two real tile positions rarely lie exactly horizontal, vertical, or
    /// 45° apart. Rather than plotting the direct line (any angle) or
    /// snapping every tile onto a rigid grid (tried, and looked like an
    /// artificial 8-spoke star, not the city), this keeps each tile's real
    /// position and instead inserts one bend between two tiles whenever
    /// their direct line isn't already one of those angles — a diagonal run
    /// covering however much of the gap is shared between both axes, then a
    /// straight run covering the rest. Any two points can always be
    /// connected this way with exactly one bend, so every segment actually
    /// drawn is a clean Tube-map angle while the tiles themselves still sit
    /// at their real, organically-shaped positions.
    ///
    /// Returns the waypoints to draw a line through *after* `start`
    /// (i.e. `[end]` when already clean, or `[bend, end]`).
    static func octilinearWaypoints(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let isAlreadyClean = dx == 0 || dy == 0 || abs(abs(dx) - abs(dy)) < 0.5
        guard !isAlreadyClean else { return [end] }

        let diagonal = min(abs(dx), abs(dy))
        let bend = CGPoint(
            x: start.x + (dx < 0 ? -diagonal : diagonal),
            y: start.y + (dy < 0 ? -diagonal : diagonal)
        )
        return [bend, end]
    }

    /// Pushes points apart pairwise until every pair is at least
    /// `minDistance` apart, moving each point in the pair equally so the
    /// overall cloud drifts as little as possible from the real geography.
    /// When `bounds` is given, every point is re-clamped inside it after
    /// each pairwise pass (not just once at the end) — clamping only once
    /// at the end can push a point back into another it had just been
    /// separated from, right at the edge of the canvas. A fixed iteration
    /// count (rather than looping until settled) keeps this a pure,
    /// deterministic function of the input — same points in, same points
    /// out, every render — which matters here since it re-runs on every
    /// SwiftUI body evaluation.
    static func declutteredPositions(
        _ rawPositions: [CGPoint],
        minDistance: CGFloat,
        bounds: CGRect? = nil,
        iterations: Int = 200
    ) -> [CGPoint] {
        guard minDistance > 0, rawPositions.count > 1 else { return rawPositions }

        func clamp(_ point: CGPoint) -> CGPoint {
            guard let bounds else { return point }
            return CGPoint(
                x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY)
            )
        }

        var points = rawPositions.map(clamp)

        for _ in 0..<iterations {
            var anyOverlap = false
            for i in points.indices {
                for j in points.indices where j > i {
                    let dx = points[j].x - points[i].x
                    let dy = points[j].y - points[i].y
                    let distance = hypot(dx, dy)
                    guard distance < minDistance else { continue }
                    anyOverlap = true

                    let (unitX, unitY): (CGFloat, CGFloat)
                    if distance > 0.0001 {
                        unitX = dx / distance
                        unitY = dy / distance
                    } else {
                        // Exactly coincident points have no direction to separate
                        // along — pick a deterministic one from their indices so
                        // they don't stay stuck on top of each other.
                        let angle = CGFloat(i * 41 + j * 17).truncatingRemainder(dividingBy: 360) * .pi / 180
                        unitX = cos(angle)
                        unitY = sin(angle)
                    }

                    let shift = (minDistance - distance) / 2
                    points[i].x -= unitX * shift
                    points[i].y -= unitY * shift
                    points[j].x += unitX * shift
                    points[j].y += unitY * shift
                }
            }
            points = points.map(clamp)
            if !anyOverlap { break }
        }
        return points
    }

    /// A distinct, deterministic color per tile index, stepped by the golden
    /// angle (≈137.5°) rather than dividing the wheel evenly — evenly-spaced
    /// hues put *adjacent* indices close together on the wheel (e.g. 40 tiles
    /// evenly spaced are only 9° apart), which is exactly the pair that ends
    /// up next to each other on screen. The golden angle keeps consecutive
    /// indices visually distinct no matter how many tiles there are.
    static func routeColor(forTileIndex index: Int) -> Color {
        let goldenAngle = 137.508
        let hue = (Double(index) * goldenAngle).truncatingRemainder(dividingBy: 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.8)
    }

    /// Visual-only waypoints along a route leg for genuinely long real-world
    /// gaps between two tiles — real geography can put two consecutive tiles
    /// far enough apart that an unbroken line reads as empty track; a few
    /// evenly-spaced stops (not real board tiles — purely decorative) keep
    /// a long leg feeling populated the way an actual transit line does.
    /// Short/typical gaps (under ~2 spacing units) get none.
    static func intermediateStops(from start: CGPoint, to end: CGPoint, spacing: CGFloat) -> [CGPoint] {
        guard spacing > 0 else { return [] }
        let waypoints = [start] + octilinearWaypoints(from: start, to: end)
        let totalLength = zip(waypoints, waypoints.dropFirst())
            .reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }

        let segments = max(1, Int((totalLength / spacing).rounded()))
        guard segments > 1 else { return [] }
        return (1..<segments).map { point(alongWaypoints: waypoints, fraction: Double($0) / Double(segments)) }
    }

    private static func point(alongWaypoints waypoints: [CGPoint], fraction: Double) -> CGPoint {
        guard waypoints.count > 1 else { return waypoints.first ?? .zero }
        let segmentLengths = zip(waypoints, waypoints.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let totalLength = segmentLengths.reduce(0, +)
        guard totalLength > 0 else { return waypoints[0] }

        let target = CGFloat(fraction) * totalLength
        var accumulated: CGFloat = 0
        for index in segmentLengths.indices {
            let segmentLength = segmentLengths[index]
            if accumulated + segmentLength >= target || index == segmentLengths.count - 1 {
                let segmentFraction = segmentLength > 0 ? (target - accumulated) / segmentLength : 0
                let p0 = waypoints[index], p1 = waypoints[index + 1]
                return CGPoint(x: p0.x + (p1.x - p0.x) * segmentFraction, y: p0.y + (p1.y - p0.y) * segmentFraction)
            }
            accumulated += segmentLength
        }
        return waypoints[waypoints.count - 1]
    }
}
