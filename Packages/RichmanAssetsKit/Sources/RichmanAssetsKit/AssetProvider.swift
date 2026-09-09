import SwiftUI

/// The art/sound/video seam: `RichmanGameUI` renders and plays everything
/// through this protocol, never by hardcoding an image/sound file name. That
/// means swapping placeholder visuals for real art from another tool/agent is
/// a change contained entirely to this package — see `Docs/ASSET_SPEC.md`.
public protocol AssetProvider: Sendable {
    func image(for key: AssetImageKey) -> Image
    func tokenColor(for playerIndex: Int) -> Color
    /// `nil` means "no sound available" — the placeholder provider returns
    /// `nil` for everything, and `RichmanGameUI` must treat that as a no-op,
    /// not a crash.
    func soundURL(for key: AssetSoundKey) -> URL?
}

public enum AssetImageKey: Hashable, Sendable {
    case diceFace(Int) // 1...6
    case playerToken(colorIndex: Int)
    case tileIcon(TileIconKind)
    case appIcon
}

public enum TileIconKind: Hashable, Sendable {
    case go, property, transit, utility, chance, communityChest, tax, jail, freeParking, goToJail
}

public enum AssetSoundKey: Hashable, Sendable {
    case diceRoll
    case purchase
    case payRent
    case collectRent
    case sentToJail
    case bankrupt
    case victory
    case buttonTap
}
