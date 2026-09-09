/// Maps a board tile index (0..<40) to its position in the classic 11x11
/// square-perimeter layout (4 corners + 9 tiles per side), independent of
/// screen size — `BoardView` multiplies these by a cell size.
enum BoardLayoutMath {
    static let gridSize = 11

    /// (col, row), both 0...10. Tile 0 (Go) is the bottom-right corner;
    /// tiles proceed counter-clockwise from there, matching the classic
    /// Monopoly-style board direction of play.
    static func gridPosition(forTileIndex index: Int) -> (col: Int, row: Int) {
        let i = ((index % 40) + 40) % 40
        switch i {
        case 0: return (10, 10)
        case 1...9: return (10 - i, 10)
        case 10: return (0, 10)
        case 11...19: return (0, 10 - (i - 10))
        case 20: return (0, 0)
        case 21...29: return (i - 20, 0)
        case 30: return (10, 0)
        default: return (10, i - 30) // 31...39
        }
    }
}
