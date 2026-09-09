import SwiftUI
import RichmanCore
import RichmanCityData
import RichmanAssetsKit
import RichmanPersistence
import RichmanGameUI

/// Scaffold placeholder. Replaced by the real board/menu flow once
/// RichmanGameUI is implemented (see Docs/ARCHITECTURE.md).
struct RootView: View {
    private let linkedModules = [
        RichmanCore.moduleName,
        RichmanCityData.moduleName,
        RichmanAssetsKit.moduleName,
        RichmanPersistence.moduleName,
        RichmanGameUI.moduleName
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Richman")
                .font(.largeTitle.bold())
            Text("Scaffold build — modules linked:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(linkedModules, id: \.self) { name in
                Text(name)
                    .font(.caption.monospaced())
            }
        }
        .padding()
    }
}

#Preview {
    RootView()
}
