import SwiftUI

/// The default `AssetProvider`: SF Symbols, solid colors, and no sound files.
/// This is what makes the game fully playable today with zero external
/// assets. Replace this (or add a `BundledAssetProvider` alongside it) once
/// real art/sound lands — see `Docs/ASSET_SPEC.md` for the exact manifest.
public struct PlaceholderAssetProvider: AssetProvider {
    public init() {}

    public func image(for key: AssetImageKey) -> Image {
        Image(systemName: Self.systemName(for: key))
    }

    public func tokenColor(for playerIndex: Int) -> Color {
        Self.tokenPalette[playerIndex % Self.tokenPalette.count]
    }

    public func soundURL(for key: AssetSoundKey) -> URL? {
        nil
    }

    static let tokenPalette: [Color] = [.red, .blue, .green, .orange, .purple, .yellow, .pink, .teal]

    static func systemName(for key: AssetImageKey) -> String {
        switch key {
        case .diceFace(let value):
            return "die.face.\(min(max(value, 1), 6))"
        case .playerToken:
            return "circle.fill"
        case .appIcon:
            return "die.face.5.fill"
        case .tileIcon(let kind):
            return systemName(for: kind)
        }
    }

    static func systemName(for tileIcon: TileIconKind) -> String {
        switch tileIcon {
        case .go: return "arrow.right.circle.fill"
        case .property: return "house.fill"
        case .transit: return "tram.fill"
        case .utility: return "bolt.fill"
        case .chance: return "questionmark.circle.fill"
        case .communityChest: return "gift.fill"
        case .tax: return "banknote.fill"
        case .jail: return "lock.fill"
        case .freeParking: return "parkingsign.circle.fill"
        case .goToJail: return "hand.raised.fill"
        }
    }
}
