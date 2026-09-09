import RichmanCityData

/// Wraps another `CityDataProvider` with an on-disk cache: a city already
/// looked up is served instantly, without hitting Nominatim/Overpass again.
/// This is the provider `RichmanApp` should actually construct — see
/// `Docs/ARCHITECTURE.md`'s "Data flow for picking a city".
public struct CachingCityDataProvider: CityDataProvider {
    private let upstream: CityDataProvider
    private let cache: CityLayoutCache

    public init(upstream: CityDataProvider, cache: CityLayoutCache = CityLayoutCache()) {
        self.upstream = upstream
        self.cache = cache
    }

    public func fetchBoardLayout(for cityName: String) async throws -> CityBoardLayout {
        if let cached = cache.layout(for: cityName) {
            return cached
        }
        let layout = try await upstream.fetchBoardLayout(for: cityName)
        try? cache.store(layout, for: cityName)
        return layout
    }
}
