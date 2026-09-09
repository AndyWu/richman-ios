import Foundation
import RichmanCore

/// Saves/loads a `GameState` as JSON on disk, so a pass-and-play game can be
/// resumed later. `directory`/`fileManager` are injectable so tests use an
/// isolated temp directory instead of the real Application Support folder.
/// `@unchecked` because `FileManager` isn't marked `Sendable` even though
/// Apple documents it as safe to use concurrently from multiple threads.
public struct GameStateStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    public func save(_ state: GameState, slot: String = "current") throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL(for: slot), options: .atomic)
    }

    public func load(slot: String = "current") throws -> GameState? {
        let url = fileURL(for: slot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GameState.self, from: data)
    }

    public func delete(slot: String = "current") throws {
        let url = fileURL(for: slot)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func hasSavedGame(slot: String = "current") -> Bool {
        fileManager.fileExists(atPath: fileURL(for: slot).path)
    }

    private func fileURL(for slot: String) -> URL {
        directory.appendingPathComponent("\(slot).json")
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Richman", isDirectory: true)
    }
}
