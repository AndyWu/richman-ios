import Foundation
import RichmanCore

/// Turns a city name into a playable `Board`. `RichmanGameUI` and `RichmanCore`
/// only ever talk to this protocol — never to Overpass/Nominatim directly —
/// so a different data source can be added later without touching game code.
public protocol CityDataProvider: Sendable {
    func fetchBoardLayout(for cityName: String) async throws -> CityBoardLayout
}

/// The result of turning a real city into a board: the board itself (built on
/// `BoardTemplate.classicSlotOrder`, so it's a drop-in `Board` for `GameState`)
/// plus a little metadata about where the data came from.
public struct CityBoardLayout: Codable, Equatable, Sendable {
    public let queriedName: String
    public let resolvedDisplayName: String
    public let board: Board
    public let fetchedAt: Date

    public init(queriedName: String, resolvedDisplayName: String, board: Board, fetchedAt: Date = Date()) {
        self.queriedName = queriedName
        self.resolvedDisplayName = resolvedDisplayName
        self.board = board
        self.fetchedAt = fetchedAt
    }
}

public enum CityDataError: Error, Equatable {
    case cityNotFound(String)
    case insufficientData(String)
    case network(String)
    case invalidResponse(String)
}
