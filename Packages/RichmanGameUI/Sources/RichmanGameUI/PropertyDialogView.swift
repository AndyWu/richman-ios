import SwiftUI
import RichmanCore

struct PropertyDialogView: View {
    let tile: Tile
    let price: Int
    let playerCash: Int
    let onBuy: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(tile.name)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("$\(price)")
                .font(.title2.bold())
            HStack(spacing: 16) {
                Button("Skip", role: .cancel, action: onDecline)
                Button("Buy", action: onBuy)
                    .buttonStyle(.borderedProminent)
                    .disabled(playerCash < price)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .padding(40)
    }
}
