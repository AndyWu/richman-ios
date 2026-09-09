import XCTest
@testable import RichmanAssetsKit

final class RichmanAssetsKitTests: XCTestCase {
    func testDiceFaceSystemNamesAreClampedToValidRange() {
        XCTAssertEqual(PlaceholderAssetProvider.systemName(for: .diceFace(1)), "die.face.1")
        XCTAssertEqual(PlaceholderAssetProvider.systemName(for: .diceFace(6)), "die.face.6")
        XCTAssertEqual(PlaceholderAssetProvider.systemName(for: .diceFace(0)), "die.face.1")
        XCTAssertEqual(PlaceholderAssetProvider.systemName(for: .diceFace(9)), "die.face.6")
    }

    func testEveryTileIconKindMapsToASystemName() {
        let kinds: [TileIconKind] = [.go, .property, .transit, .utility, .chance, .communityChest, .tax, .jail, .freeParking, .goToJail]
        for kind in kinds {
            XCTAssertFalse(PlaceholderAssetProvider.systemName(for: kind).isEmpty)
        }
    }

    func testTokenColorCyclesThroughPaletteForOutOfRangeIndices() {
        let provider = PlaceholderAssetProvider()
        let paletteSize = PlaceholderAssetProvider.tokenPalette.count
        XCTAssertEqual(provider.tokenColor(for: 0), provider.tokenColor(for: paletteSize))
        XCTAssertNotEqual(provider.tokenColor(for: 0), provider.tokenColor(for: 1))
    }

    func testPlaceholderProviderHasNoSounds() {
        let provider = PlaceholderAssetProvider()
        XCTAssertNil(provider.soundURL(for: .diceRoll))
        XCTAssertNil(provider.soundURL(for: .victory))
    }
}
