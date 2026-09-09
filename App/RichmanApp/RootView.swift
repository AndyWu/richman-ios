import SwiftUI
import RichmanCityData
import RichmanPersistence
import RichmanGameUI

/// Composition root: wires the real `CityDataProvider` stack (bundled demo
/// cities first, then a live OSM fetch for anything else, all cached to
/// disk) and hands it to `GameRootView`. See `Docs/ARCHITECTURE.md`.
struct RootView: View {
    var body: some View {
        GameRootView(cityDataProvider: Self.makeCityDataProvider())
    }

    private static func makeCityDataProvider() -> CityDataProvider {
        let live = OSMCityDataProvider()
        let withBundledFallback = BundledCityDataProvider(fallback: live)
        return CachingCityDataProvider(upstream: withBundledFallback)
    }
}

#Preview {
    RootView()
}
