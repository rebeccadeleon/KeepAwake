import SwiftUI
import Charts

struct BatterySettingsView: View {
    @ObservedObject var manager: BatteryMonitor

    @State private var historyHours = 24
    @State private var showClearConfirmation = false

    private var battery: BatteryInformation? {
        manager.information
    }

    private var filteredHistory: [BatterySample] {
        let cutoff = Date().addingTimeInterval(
            -Double(historyHours) * 3600
        )

        return manager.history.filter {
            $0.timestamp >= cutoff
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let battery {
                        batteryOverview(battery)

                        informationCards(battery)

                        historySection

                        protectionSection
                    } else {
                        unavailableView
                    }
                }
                .padding(16)
            }

            Divider()

            footer
                .padding(12)
        }
        .alert(
            "Clear Battery History?",
            isPresented: $showClearConfirmation
        ) {
            Button("Cancel", role: .cancel) {}

            Button("Clear", role: .destructive) {
                manager.clearHistory()
            }
        } message: {
            Text("All recorded battery samples will be deleted.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.100")
                .font(.system(size: 26))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("Battery Management")
                    .font(.system(
                        size: 16,
                        weight: .semibold
                    ))

                Text("Power information and battery protection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh battery information")
        }
    }

    // MARK: - Overview

    private func batteryOverview(
        _ battery: BatteryInformation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(
                    systemName: batteryIcon(battery)
                )
                .font(.system(size: 42))
                .foregroundStyle(
                    batteryColor(battery.percentage)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(battery.percentage)%")
                        .font(.system(
                            size: 32,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .monospacedDigit()

                    Text(battery.chargingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(
                    battery.powerSource,
                    systemImage: battery.onBattery
                        ? "battery.75"
                        : "powerplug.fill"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(battery.percentage),
                total: 100
            )
            .tint(
                batteryColor(battery.percentage)
            )
        }
        .padding(16)
        .background(
            Color.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: - Information

    private func informationCards(
        _ battery: BatteryInformation
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            informationCard(
                title: "Estimated battery health",
                value: battery.healthPercentage.map {
                    String(format: "%.1f%%", $0)
                } ?? "Unavailable",
                icon: "heart.fill",
                color: .green
            )

            informationCard(
                title: "Cycle count",
                value: battery.cycleCount.map {
                    String($0)
                } ?? "Unavailable",
                icon: "arrow.triangle.2.circlepath",
                color: .blue
            )

            informationCard(
                title: "Time remaining",
                value: battery.onBattery
                    ? formatMinutes(battery.timeToEmpty)
                    : "—",
                icon: "clock",
                color: .orange
            )

            informationCard(
                title: "Time until full",
                value: battery.isCharging
                    ? formatMinutes(battery.timeToFull)
                    : "—",
                icon: "bolt.fill",
                color: .purple
            )
        }
    }

    private func informationCard(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(
                    size: 20,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(14)
        .background(
            Color.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Battery Level History")
                    .font(.system(
                        size: 13,
                        weight: .semibold
                    ))

                Spacer()

                Picker(
                    "",
                    selection: $historyHours
                ) {
                    Text("6 hours").tag(6)
                    Text("24 hours").tag(24)
                    Text("7 days").tag(168)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            if filteredHistory.isEmpty {
                Text("No battery history available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 150
                    )
            } else {
                Chart {
                    ForEach(filteredHistory) { sample in
                        AreaMark(
                            x: .value(
                                "Time",
                                sample.timestamp
                            ),
                            y: .value(
                                "Charge",
                                sample.percentage
                            )
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    .green.opacity(0.25),
                                    .green.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value(
                                "Time",
                                sample.timestamp
                            ),
                            y: .value(
                                "Charge",
                                sample.percentage
                            )
                        )
                        .foregroundStyle(.green)
                        .lineStyle(
                            StrokeStyle(lineWidth: 2)
                        )
                    }

                    if manager.pauseOnLowBattery {
                        RuleMark(
                            y: .value(
                                "Pause",
                                manager.effectivePauseThreshold
                            )
                        )
                        .foregroundStyle(.red.opacity(0.7))
                        .lineStyle(
                            StrokeStyle(dash: [4, 4])
                        )

                        RuleMark(
                            y: .value(
                                "Resume",
                                manager.effectiveResumeThreshold
                            )
                        )
                        .foregroundStyle(.blue.opacity(0.7))
                        .lineStyle(
                            StrokeStyle(dash: [4, 4])
                        )
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: [0, 25, 50, 75, 100]
                    ) { value in
                        AxisGridLine()

                        AxisValueLabel {
                            if let level = value.as(Int.self) {
                                Text("\(level)%")
                            }
                        }
                    }
                }
                .frame(height: 170)
            }

            HStack(spacing: 16) {
                Label(
                    "Battery level",
                    systemImage: "minus"
                )
                .foregroundStyle(.green)

                if manager.pauseOnLowBattery {
                    Label(
                        "Pause threshold",
                        systemImage: "minus"
                    )
                    .foregroundStyle(.red)

                    Label(
                        "Resume threshold",
                        systemImage: "minus"
                    )
                    .foregroundStyle(.blue)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(
            Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Protection

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Battery Protection")
                .font(.system(
                    size: 13,
                    weight: .semibold
                ))

            Toggle(
                "Pause sleep prevention on low battery",
                isOn: $manager.pauseOnLowBattery
            )

            if manager.pauseOnLowBattery {
                thresholdSlider(
                    title: "Pause threshold",
                    value: Binding(
                        get: {
                            Double(
                                manager.effectivePauseThreshold
                            )
                        },
                        set: {
                            manager.setPauseThreshold(Int($0))
                        }
                    ),
                    range: 5...50
                )

                thresholdSlider(
                    title: "Resume threshold",
                    value: Binding(
                        get: {
                            Double(
                                manager.effectiveResumeThreshold
                            )
                        },
                        set: {
                            manager.setResumeThreshold(Int($0))
                        }
                    ),
                    range: Double(
                        manager.effectivePauseThreshold + 5
                    )...100
                )

                Text(
                    "Sleep prevention resumes when the battery " +
                    "reaches the resume threshold or AC power " +
                    "is connected."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            Toggle(
                "Only prevent sleep on AC power",
                isOn: $manager.acPowerOnly
            )

            Text(
                "Applies to manual sessions and all automatic " +
                "sleep prevention rules."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if manager.isProtectionActive {
                Label(
                    manager.protectionReason ??
                        "Battery protection active",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .background(
            Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func thresholdSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(value.wrappedValue))%")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            Slider(
                value: value,
                in: range,
                step: 5
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let date = manager.lastUpdated {
                Text(
                    "Updated: " +
                    date.formatted(
                        date: .omitted,
                        time: .standard
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear History") {
                showClearConfirmation = true
            }
            .disabled(manager.history.isEmpty)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "battery.0")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No internal battery detected")
                .font(.headline)

            Text(
                "Battery management is available on Macs " +
                "with a supported internal battery."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 240
        )
    }

    // MARK: - Helpers

    private func formatMinutes(
        _ minutes: Int?
    ) -> String {
        guard let minutes else {
            return "Calculating..."
        }

        let hours = minutes / 60
        let remaining = minutes % 60

        if hours == 0 {
            return "\(remaining) min"
        }

        return "\(hours)h \(remaining)m"
    }

    private func batteryColor(
        _ percentage: Int
    ) -> Color {
        if percentage <= 10 {
            return .red
        }

        if percentage <= 20 {
            return .orange
        }

        return .green
    }

    private func batteryIcon(
        _ battery: BatteryInformation
    ) -> String {
        if battery.isCharging {
            return "battery.100.bolt"
        }

        switch battery.percentage {
        case 0...10:
            return "battery.0"
        case 11...35:
            return "battery.25"
        case 36...60:
            return "battery.50"
        case 61...85:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
}