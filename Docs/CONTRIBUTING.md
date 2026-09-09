# Contributing (including for AI agents)

This repo is deliberately structured so multiple people or AI tools can work in it at once without stepping on each other. If you're an AI coding agent that's been pointed at this repo, read this file first.

## Ground rules

- **Never commit directly to `main`.** Create a branch, push it, open a PR.
- **Branch naming:** `feature/<short-name>` for new functionality, `fix/<short-name>` for bug fixes, `chore/<short-name>` for tooling/docs/refactors, `art/<short-name>` for asset-only changes.
- **One logical change per PR.** If you're adding both a game rule and a UI screen, that's two PRs.
- **Every PR must build and pass tests before you open it** — see "Building and testing" below. Don't rely on CI to find compile errors you could've caught locally.
- **Stay inside your module's boundary** (see [`ARCHITECTURE.md`](ARCHITECTURE.md)). If you find yourself wanting to `import SwiftUI` in `RichmanCore`, stop — that logic belongs in `RichmanGameUI` instead, talking to `RichmanCore` through its public types.
- **Don't hand-edit `RichmanApp.xcodeproj`.** It's generated from `project.yml` by XcodeGen. Edit `project.yml` and run `xcodegen generate`. (The generated `.xcodeproj` is gitignored — don't fight the ignore rule.)

## Building and testing

You do **not** need to open Xcode to work on `RichmanCore`, `RichmanCityData`, `RichmanAssetsKit`, or `RichmanPersistence` — they're plain Swift packages:

```bash
cd Packages/RichmanCore
swift build
swift test
```

Do this for whichever package(s) you touched before opening a PR.

If you're changing `RichmanGameUI` or `App/`, you need full Xcode (not just Command Line Tools — check with `xcode-select -p`; it should point at `/Applications/Xcode.app/Contents/Developer`) plus [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # once
xcodegen generate
open RichmanApp.xcodeproj
```

Then build/run the `RichmanApp` scheme on an iOS Simulator.

## Adding real art, sound, or video assets

This is the main way we expect a separate AI agent to contribute. See [`ASSET_SPEC.md`](ASSET_SPEC.md) for the exact manifest of what's needed (keys, dimensions, style). In short:

1. Drop asset files into `Packages/RichmanAssetsKit/Sources/RichmanAssetsKit/Resources/`.
2. Wire them up by implementing `AssetProvider` (or extending the existing implementation) in `RichmanAssetsKit` — do not touch `RichmanGameUI` or any other package to do this.
3. Open a PR on a branch named `art/<what-you-added>`.
4. `swift test` in `Packages/RichmanAssetsKit` should still pass.

## Opening a PR

```bash
git checkout -b feature/my-change
# ... make changes, commit ...
git push -u origin feature/my-change
gh pr create --fill
```

Include in the PR description: what changed, why, and how you verified it (which `swift test` runs you ran, or which Simulator build you tried).

## Code style

- Swift API Design Guidelines naming (no Hungarian notation, no abbreviations).
- Prefer `struct`/value types and protocols over classes/inheritance, consistent with the rest of the codebase.
- No force-unwraps (`!`) or force-tries (`try!`) outside of tests.
- Keep comments to the "why", not the "what" — see the top-level project conventions.
