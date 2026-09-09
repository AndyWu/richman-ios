import SwiftUI
import RichmanCore
import RichmanAssetsKit

struct PlayerHUDView: View {
    let players: [Player]
    let currentPlayerIndex: Int
    let assetProvider: AssetProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                HStack {
                    Circle()
                        .fill(assetProvider.tokenColor(for: index))
                        .frame(width: 12, height: 12)
                    Text(player.name)
                        .fontWeight(index == currentPlayerIndex ? .bold : .regular)
                    Spacer()
                    if player.isBankrupt {
                        Text("Bankrupt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if player.isInJail {
                            Image(systemName: "lock.fill").font(.caption)
                        }
                        Text("$\(player.cash)")
                            .monospacedDigit()
                    }
                }
                .opacity(player.isBankrupt ? 0.5 : 1)
            }
        }
    }
}
