import SwiftUI
import Charts

struct ResourceSettingsView: View {
    @ObservedObject var manager: ResourceMonitor

    private var sample: ResourceSample? {
        manager.latest
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    resourceCards

                    protectionSection

                    configurationSection
                }
                .padding(16)
            }

            Divider()

            footer
                .padding(12)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 26))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text("System Resources")
                    .font(.system(
                        size: 16,
                        weight: .semibold
                    ))

                Text("Real-time system activity monitoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "Enable monitoring",
                isOn: $manager.preferences.isEnabled
            )
            .toggleStyle(.switch)
        }
    }

    // MARK: - Resource cards

    private var resourceCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {
            resourceCard(
                title: "CPU usage",
                value: ResourceFormatter.percentage(
                    sample?.cpuUsage
                ),
                detail: "Overall CPU utilization",
                icon: "cpu",
                color: .blue,
                metric: { $0.cpuUsage },
                percentage: true
            )

            resourceCard(
                title: "Memory usage",
                value: ResourceFormatter.bytes(
                    sample?.memoryUsed
                ),
                detail: memoryDetail,
                icon: "memorychip",
                color: .purple,
                metric: { $0.memoryUsage },
                percentage: true
            )

            resourceCard(
                title: "Network activity",
                value: ResourceFormatter.speed(
                    sample?.networkSpeed
                ),
                detail: networkDetail,
                icon: "network",
                color: .green,
                metric: {
                    $0.networkSpeed.map {
                        $0 / 1_000_000
                    }
                }
            )

            resourceCard(
                title: "Disk activity",
                value: ResourceFormatter.speed(
                    sample?.diskSpeed
                ),
                detail: diskDetail,
                icon: "internaldrive",
                color: .orange,
                metric: {
                    $0.diskSpeed.map {
                        $0 / 1_000_000
                    }
                }
            )
        }
    }

    private var memoryDetail: String {
        let total = ResourceFormatter.bytes(
            sample?.memoryTotal ??
            ProcessInfo.processInfo.physicalMemory
        )

        return "\(total) physical memory"
    }

    private var networkDetail: String {
        let download = ResourceFormatter.speed(
            sample?.downloadSpeed
        )

        let upload = ResourceFormatter.speed(
            sample?.uploadSpeed
        )

        return "↓ \(download)  ↑ \(upload)"
    }

    private var diskDetail: String {
        let read = ResourceFormatter.speed(
            sample?.diskReadSpeed
        )

        let write = ResourceFormatter.speed(
            sample?.diskWriteSpeed
        )

        return "Read \(read) · Write \(write)"
    }

    private func resourceCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color,
        metric: @escaping (ResourceSample) -> Double?,
        percentage: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(
                    size: 26,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(color)
                .monospacedDigit()

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            resourceChart(
                color: color,
                metric: metric,
                percentage: percentage
            )
            .frame(height: 65)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.secondary.opacity(0.12)
                )
        }
    }

    private func resourceChart(
        color: Color,
        metric: @escaping (ResourceSample) -> Double?,
        percentage: Bool
    ) -> some View {
        let maximum = percentage
            ? 100.0
            : max(
                1.0,
                manager.history.compactMap(metric).max() ?? 1
            )

        return Chart(manager.history) { sample in
            if let value = metric(sample) {
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Usage", value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            color.opacity(0.20),
                            color.opacity(0.01)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Usage", value)
                )
                .foregroundStyle(color)
                .lineStyle(
                    StrokeStyle(lineWidth: 1.5)
                )
            }
        }
        .chartYScale(domain: 0...maximum)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    // MARK: - Automatic protection

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Automatic Sleep Prevention")
                .font(.system(
                    size: 13,
                    weight: .semibold
                ))

            protectionRow(
                title: "High CPU activity",
                icon: "cpu",
                enabled: $manager.preferences.cpuProtection,
                threshold: $manager.preferences.cpuThreshold,
                range: 5...95,
                step: 5,
                unit: "%",
                active: manager.cpuProtectionActive
            )

            Divider()

            protectionRow(
                title: "Network transfers",
                icon: "network",
                enabled:
                    $manager.preferences.networkProtection,
                threshold:
                    $manager.preferences.networkThreshold,
                range: 0.5...100,
                step: 0.5,
                unit: "MB/s",
                active: manager.networkProtectionActive
            )

            Divider()

            protectionRow(
                title: "Disk activity",
                icon: "internaldrive",
                enabled:
                    $manager.preferences.diskProtection,
                threshold:
                    $manager.preferences.diskThreshold,
                range: 1...200,
                step: 1,
                unit: "MB/s",
                active: manager.diskProtectionActive
            )
        }
        .padding(14)
        .background(
            Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func protectionRow(
        title: String,
        icon: String,
        enabled: Binding<Bool>,
        threshold: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        active: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12))

                Spacer()

                if active {
                    Text("Triggered")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(title)
            }

            if enabled.wrappedValue {
                HStack {
                    Text("Activation threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(
                        String(
                            format: "%.1f %@",
                            threshold.wrappedValue,
                            unit
                        )
                    )
                    .font(.system(
                        size: 12,
                        weight: .medium
                    ))
                    .monospacedDigit()
                }

                Slider(
                    value: threshold,
                    in: range,
                    step: step
                )

                Text(
                    "Releases below " +
                    String(
                        format: "%.1f %@",
                        threshold.wrappedValue * 0.8,
                        unit
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring Configuration")
                .font(.system(
                    size: 13,
                    weight: .semibold
                ))

            HStack {
                Text("Sampling interval")

                Spacer()

                Picker(
                    "",
                    selection:
                        $manager.preferences.samplingInterval
                ) {
                    Text("1 second").tag(1.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .frame(width: 130)
            }

            HStack {
                Text("Activation delay")

                Spacer()

                Picker(
                    "",
                    selection:
                        $manager.preferences.activationDelay
                ) {
                    Text("Immediately").tag(0.0)
                    Text("5 seconds").tag(5.0)
                    Text("9 seconds").tag(9.0)
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                }
                .frame(width: 130)
            }

            HStack {
                Text("Release delay")

                Spacer()

                Picker(
                    "",
                    selection:
                        $manager.preferences.releaseDelay
                ) {
                    Text("Immediately").tag(0.0)
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                }
                .frame(width: 130)
            }

            Text(
                "Resource triggers respect manual pause " +
                "and low battery protection."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(14)
        .background(
            Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Circle()
                .fill(
                    manager.isMonitoring
                        ? Color.green
                        : Color.secondary
                )
                .frame(width: 7, height: 7)

            Text(
                manager.isMonitoring
                    ? "Monitoring active"
                    : "Monitoring disabled"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if manager.hasActiveProtection {
                Text("· Sleep prevention requested")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Button("Restore Defaults") {
                manager.restoreDefaults()
            }
        }
    }
}