import SwiftUI
import RichmanCore
import RichmanAssetsKit

struct TileView: View {
    let tile: Tile
    let tileState: TileState
    let ownerColor: Color?
    let assetProvider: AssetProvider

    var body: some View {
        VStack(spacing: 1) {
            assetProvider.image(for: .tileIcon(iconKind))
                .font(.system(size: 9))
            Text(tile.name)
                .font(.system(size: 7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if case .property(let details) = tile.category {
                Text("$\(details.price)")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)
            }
            if tileState.buildingLevel > 0 {
                Text(tileState.buildingLevel >= 5 ? "🏨" : String(repeating: "🏠", count: tileState.buildingLevel))
                    .font(.system(size: 6))
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(tileState.isMortgaged ? 0.25 : 0.08))
        .overlay(Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5))
        .overlay(alignment: .top) {
            if let ownerColor {
                Rectangle().fill(ownerColor).frame(height: 3)
            }
        }
    }

    private var iconKind: TileIconKind {
        switch tile.category {
        case .go: return .go
        case .property: return .property
        case .transit: return .transit
        case .utility: return .utility
        case .chance: return .chance
        case .communityChest: return .communityChest
        case .tax: return .tax
        case .jail: return .jail
        case .freeParking: return .freeParking
        case .goToJail: return .goToJail
        }
    }
}
