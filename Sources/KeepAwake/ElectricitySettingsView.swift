import SwiftUI

struct ElectricitySettingsView: View {
    @ObservedObject var manager:
        ElectricityPriceManager

    var body: some View {
        Form {
            Section("Energy rule") {
                Toggle(
                    "Enable electricity price rule",
                    isOn: $manager.isEnabled
                )

                TextField(
                    "HTTPS price API",
                    text: $manager.endpoint
                )

                HStack {
                    Text("Maximum price per kWh")

                    Spacer()

                    TextField(
                        "Price",
                        value: $manager.maximumPrice,
                        format: .number
                    )
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                }

                Text(
                    "KeepAwake activates an automatic " +
                    "session when the current electricity " +
                    "price is at or below this threshold."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Current electricity price") {
                if let price = manager.currentPrice {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(
                                price.price.formatted(
                                    .number.precision(
                                        .fractionLength(2)
                                    )
                                )
                            )
                            .font(.system(
                                size: 30,
                                weight: .semibold
                            ))
                            .monospacedDigit()

                            Text("\(price.currency)/kWh")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(
                            systemName: manager.isLowPrice
                                ? "bolt.circle.fill"
                                : "bolt.circle"
                        )
                        .font(.system(size: 34))
                        .foregroundStyle(
                            manager.isLowPrice
                                ? Color.green
                                : Color.secondary
                        )
                    }

                    LabeledContent(
                        "Valid until",
                        value: price.validUntil.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )

                    Label(
                        manager.isLowPrice
                            ? "Energy rule active"
                            : "Above price threshold",
                        systemImage: manager.isLowPrice
                            ? "checkmark.circle.fill"
                            : "pause.circle"
                    )
                    .foregroundStyle(
                        manager.isLowPrice
                            ? Color.green
                            : Color.secondary
                    )
                } else {
                    Text("No electricity price available")
                        .foregroundStyle(.secondary)
                }

                if let checked = manager.lastChecked {
                    LabeledContent(
                        "Last checked",
                        value: checked.formatted(
                            date: .omitted,
                            time: .standard
                        )
                    )
                }

                if let error = manager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Refresh Price") {
                    Task {
                        await manager.refresh()
                    }
                }
                .disabled(
                    !manager.isEnabled ||
                    manager.isChecking
                )
            }
        }
        .formStyle(.grouped)
    }
}