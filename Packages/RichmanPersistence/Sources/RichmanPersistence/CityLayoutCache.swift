import Foundation
import RichmanCityData

/// Caches `CityBoardLayout` results on disk, keyed by normalized city name,
/// so a city is only geocoded/queried once, even across app launches.
/// `@unchecked` because `FileManager` isn't marked `Sendable` even though
/// Apple documents it as safe to use concurrently from multiple threads.
public struct CityLayoutCache: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    public func layout(for cityName: String) -> CityBoardLayout? {
        guard let data = try? Data(contentsOf: fileURL(for: cityName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CityBoardLayout.self, from: data)
    }

    public func store(_ layout: CityBoardLayout, for cityName: String) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(layout)
        try data.write(to: fileURL(for: cityName), options: .atomic)
    }

    public func clear(cityName: String) throws {
        let url = fileURL(for: cityName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for cityName: String) -> URL {
        directory.appendingPathComponent("\(Self.normalize(cityName)).json")
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Richman/CityLayouts", isDirectory: true)
    }
}
