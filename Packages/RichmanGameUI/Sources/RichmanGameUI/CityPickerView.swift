import SwiftUI

struct CityPickerView: View {
    @State private var cityName: String = ""
    @State private var playerCount: Int = 2

    let isLoading: Bool
    let message: String?
    let onStart: (String?, [String]) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Richman")
                .font(.largeTitle.bold())
            Text("Pick a real city for your board, or leave it blank for a generic one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("City (e.g. New York)", text: $cityName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .disableAutocorrection(true)

            Stepper("Players: \(playerCount)", value: $playerCount, in: 2...6)
                .padding(.horizontal)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                let names = (1...playerCount).map { "Player \($0)" }
                onStart(cityName.isEmpty ? nil : cityName, names)
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Start Game")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
            .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
}
