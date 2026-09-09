import RichmanCore

/// Instant, offline `CityDataProvider` for unit tests and SwiftUI previews —
/// makes no network calls. Defaults to the generic `StandardBoard`.
public struct MockCityDataProvider: CityDataProvider {
    private let board: Board
    private let resolvedDisplayName: String
    private let errorToThrow: CityDataError?

    public init(board: Board = StandardBoard.classic40Tile(), resolvedDisplayName: String = "Mock City", throwing error: CityDataError? = nil) {
        self.board = board
        self.resolvedDisplayName = resolvedDisplayName
        self.errorToThrow = error
    }

    public func fetchBoardLayout(for cityName: String) async throws -> CityBoardLayout {
        if let errorToThrow { throw errorToThrow }
        return CityBoardLayout(queriedName: cityName, resolvedDisplayName: resolvedDisplayName, board: board)
    }
}
