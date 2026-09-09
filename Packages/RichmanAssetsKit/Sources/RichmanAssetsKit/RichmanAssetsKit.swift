/// The art/sound/video seam. Ships a placeholder `AssetProvider` so the game
/// is fully playable with no external assets; other tools/agents can add a
/// real implementation without touching game or UI code. See `Docs/ASSET_SPEC.md`.
public enum RichmanAssetsKit {
    public static let moduleName = "RichmanAssetsKit"
}
