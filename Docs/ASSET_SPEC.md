# Asset spec (for AI art/sound agents)

This is the manifest for replacing `RichmanAssetsKit`'s placeholder visuals/sounds with real ones. If you're an AI agent generating art or audio for this repo, this file is your source of truth — you shouldn't need to read any other Swift code to do the job.

**You never need to touch `RichmanGameUI` or any other package.** Every image and sound the game uses is requested through `AssetProvider` (`Packages/RichmanAssetsKit/Sources/RichmanAssetsKit/AssetProvider.swift`), by key, not by hardcoded filename. Your job is entirely inside `RichmanAssetsKit`.

## Visual direction

The reference is **大富翁 1/2/3** (Taiwan, early-to-mid 1990s): a top-down, square board; chunky, colorful, slightly cartoonish pixel-art tiles and character tokens; bold black outlines; saturated primary colors; a cheerful, arcade-y feel rather than a realistic one. Not the muted, corporate look of modern digital Monopoly.

## What's requested, by key

### Images (`AssetImageKey`, in `AssetProvider.swift`)

| Key | Count | What it is | Suggested size |
|---|---|---|---|
| `.diceFace(1...6)` | 6 | One die face per value | 128×128 px, square, transparent background |
| `.playerToken(colorIndex: 0...7)` | up to 8 | A player's board piece — pick a recognizable, distinct icon per index (not just a colored circle), the way the original game's pieces (car, dog, hat, ship...) were distinct | 128×128 px, square, transparent background |
| `.tileIcon(kind)` | 10 (one per `TileIconKind` case: `go`, `property`, `transit`, `utility`, `chance`, `communityChest`, `tax`, `jail`, `freeParking`, `goToJail`) | A small icon shown on every board tile of that category | 64×64 px, square, transparent background |
| `.appIcon` | 1 | The app icon | 1024×1024 px, no transparency (App Store requirement) |

### Sounds (`AssetSoundKey`, in `AssetProvider.swift`)

| Key | Moment it plays |
|---|---|
| `.diceRoll` | Dice are rolled |
| `.purchase` | A player buys a tile |
| `.payRent` | A player pays rent |
| `.collectRent` | A player receives rent |
| `.sentToJail` | A player is sent to jail |
| `.bankrupt` | A player goes bankrupt |
| `.victory` | The game ends |
| `.buttonTap` | Generic UI button feedback |

Short (under ~2 seconds), `.m4a` or `.caf`, mono is fine.

## Where files go

Drop finished files into:

```
Packages/RichmanAssetsKit/Sources/RichmanAssetsKit/Resources/
```

Add them as a package resource in `Packages/RichmanAssetsKit/Package.swift` (a `.copy(...)` or `.process(...)` entry in the target's `resources:` array — see how `RichmanCityData/Package.swift` does this for its bundled city JSON as a reference).

## Wiring it up

Implement a new `AssetProvider` (e.g. `BundledAssetProvider`) alongside `PlaceholderAssetProvider` in the same package:

```swift
public struct BundledAssetProvider: AssetProvider {
    public func image(for key: AssetImageKey) -> Image {
        Image(fileName(for: key), bundle: .module)
    }
    public func tokenColor(for playerIndex: Int) -> Color { /* can stay palette-based, or ignored once tokens are real art */ }
    public func soundURL(for key: AssetSoundKey) -> URL? {
        Bundle.module.url(forResource: fileName(for: key), withExtension: "m4a")
    }
    // ...
}
```

Then change one line in `App/RichmanApp/RootView.swift` (`GameRootView(cityDataProvider:assetProvider:)`) to pass your new provider instead of `PlaceholderAssetProvider()`. That's the entire integration surface.

## Opening the PR

Branch name: `art/<short-description>` (e.g. `art/tile-icons-v1`). Run `swift test` in `Packages/RichmanAssetsKit` before opening the PR — see `Docs/CONTRIBUTING.md`.
