import SwiftUI

/// The settings sheet: animation speed, theme, sound volume, and (only
/// while a game is in progress) a way to abandon it and return to the city
/// picker. Reachable from the gear icon `GameRootView` overlays on both the
/// city picker and the in-game screen.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let isGameInProgress: Bool
    let onRestartGame: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRestartConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Animation Speed") {
                    Picker("Animation Speed", selection: $settings.animationSpeed) {
                        ForEach(AnimationSpeed.allCases) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.soundVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sound Volume")
                } footer: {
                    Text("No sound effects are included yet — this is ready for when they are.")
                }

                if isGameInProgress {
                    Section {
                        Button("Restart Game", role: .destructive) {
                            isShowingRestartConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Restart the game?",
                isPresented: $isShowingRestartConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restart Game", role: .destructive) {
                    onRestartGame()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This ends the current game for all players and returns to the city picker. This can't be undone.")
            }
        }
    }
}
