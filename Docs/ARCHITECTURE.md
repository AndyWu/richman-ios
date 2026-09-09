# Architecture

Richman iOS is built as a thin SwiftUI app shell over five independent Swift packages. This keeps the game engine, real-city data pipeline, art/sound assets, persistence, and UI cleanly separated so different people (or AI agents) can work on one module without needing to understand or touch the others.

```
                    ┌───────────────┐
                    │  RichmanApp   │   (App/ — SwiftUI app shell, composition root)
                    └───────┬───────┘
                            │ depends on
              ┌─────────────┼─────────────┬───────────────┐
              ▼             ▼             ▼               ▼
      RichmanGameUI   RichmanCityData  RichmanPersistence  RichmanAssetsKit
              │             │               │
              │             ▼               │
              │        RichmanCore ◀────────┘
              └─────────────┘
       (RichmanGameUI also depends on RichmanCore directly, to drive GameEngine)
```

`RichmanCore` is the one package everything else ultimately depends on (directly or via `RichmanCityData`); it depends on nothing itself.

## Modules

| Package | Responsibility | Depends on | UIKit/SwiftUI? | Network? |
|---|---|---|---|---|
| `RichmanCore` | Board, players, turns, cards, economy — the actual game rules. Also defines `BoardTemplate`, the shared 40-slot shape/pricing both `StandardBoard` and `RichmanCityData` build boards from. | nothing | no | no |
| `RichmanCityData` | Turns a city name into a `CityBoardLayout` (a real `RichmanCore.Board` built from real streets/stations/landmarks). | `RichmanCore` (for `Board`/`BoardTemplate`) | no | yes (Nominatim + Overpass) |
| `RichmanAssetsKit` | `AssetProvider` protocol + placeholder implementation. The seam other tools plug real art/sound into. | nothing | SwiftUI (`Image`) | no |
| `RichmanPersistence` | Save/load `GameState` and cache `CityBoardLayout` results to disk. | `RichmanCore`, `RichmanCityData` (for the types it persists) | no | no |
| `RichmanGameUI` | All SwiftUI views: board, HUD, dice, dialogs. | `RichmanCore`, `RichmanCityData`, `RichmanAssetsKit` | yes | no |
| `RichmanApp` (App/) | Composition root: picks concrete providers, builds the engine, shows `RichmanGameUI`. | all of the above | yes | no |

**Rule of thumb:** if you're adding game rules, you're in `RichmanCore`. If you're adding a way to look up real-world places, you're in `RichmanCityData`. If you're adding an image/sound, you're in `RichmanAssetsKit` (see [`ASSET_SPEC.md`](ASSET_SPEC.md)). If you're adding a screen or animation, you're in `RichmanGameUI`. Nothing outside `RichmanGameUI` and `App/` should import SwiftUI or UIKit.

## Why separate Swift packages instead of one Xcode target

Every package except the App target is plain Swift Package Manager, so it can be built and tested with `swift build` / `swift test` alone — no Xcode project needed. That means:
- CI (and any AI agent) can verify a change compiles and its tests pass without opening Xcode.
- Module boundaries are enforced by the compiler (e.g. `RichmanCore` literally cannot `import SwiftUI`), not just convention.
- Swapping `RichmanAssetsKit`'s placeholder implementation for real art, or adding a second `RichmanCityData` provider, is a change contained to one package.

The Xcode project itself (`App/RichmanApp.xcodeproj`) is **generated**, not hand-maintained — see [XcodeGen](https://github.com/yonaskolb/XcodeGen) and `project.yml` at the repo root. Never edit the `.xcodeproj` directly; edit `project.yml` and run `xcodegen generate`.

## Data flow for picking a city

1. User enters a city name in `RichmanGameUI`.
2. `RichmanGameUI` calls a `CityDataProvider` (protocol defined in `RichmanCityData`) to fetch a `CityBoardLayout`.
3. `RichmanPersistence` is checked first for a cached layout; on a miss, the real `OSMCityDataProvider` geocodes the city (Nominatim) and queries Overpass for roads/stations/landmarks, then the result is cached.
4. The `CityBoardLayout` is handed to `RichmanCore` to build a `Board`, which drives the actual game.
5. `RichmanGameUI` renders the `Board` using placeholder (or, later, real) assets from `RichmanAssetsKit`.

See [`CITY_DATA.md`](CITY_DATA.md) for the full algorithm.
