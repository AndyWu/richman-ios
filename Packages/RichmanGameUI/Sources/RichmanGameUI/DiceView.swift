import SwiftUI
import RichmanCore
import RichmanAssetsKit

struct DiceView: View {
    let roll: DiceRoll?
    let assetProvider: AssetProvider

    var body: some View {
        HStack(spacing: 8) {
            die(roll?.die1)
            die(roll?.die2)
        }
    }

    private func die(_ value: Int?) -> some View {
        assetProvider.image(for: .diceFace(value ?? 1))
            .font(.system(size: 32))
            .opacity(value == nil ? 0.25 : 1)
    }
}
