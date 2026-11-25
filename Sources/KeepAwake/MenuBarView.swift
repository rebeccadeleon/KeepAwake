import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var manager: SleepManager
    @ObservedObject var battery: BatteryMonitor

    @Environment(\.openWindow) private var openWindow

    @AppStorage("selectedSessionMinutes")
    private var selectedMinutes = 60

    @State private var customHours = 1
    @State private var customMinutes = 0
    @State private var showCustomDuration = false

    private let durations = [
        15, 30, 60, 120, 240, 480, 0
    ]

    var body: some View {
        VStack(spacing: 14) {
            header

            Divider()

            statusSection

            durationSection

            if manager.isManualActive,
               manager.endDate != nil {
                extensionSection
            }

            Divider()

            optionsSection

            if let error = manager.assertionError {
                errorSection(error)
            }

            actionSection

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "power")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("KeepAwake")
                    .font(.system(size: 16, weight: .semibold))

                Text("Power & sleep manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    manager.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.08))

                    Circle()
                        .strokeBorder(
                            statusColor.opacity(0.6),
                            lineWidth: 2
                        )

                    Image(systemName: statusIcon)
                        .font(.system(
                            size: 38,
                            weight: .medium
                        ))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 100, height: 100)
            }
            .buttonStyle(.plain)
            .help("Toggle KeepAwake")

            Text(manager.statusText)
                .font(.system(size: 17, weight: .semibold))

            if let remaining = manager.remainingText {
                Text(remaining)
                    .font(.system(
                        size: 28,
                        weight: .medium,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(statusColor)
            }

            Text(manager.reasonText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session duration")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6),
                    count: 4
                ),
                spacing: 6
            ) {
                ForEach(durations, id: \.self) { minutes in
                    durationButton(minutes)
                }

                Button {
                    showCustomDuration.toggle()
                } label: {
                    Text("Custom")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    Color.secondary.opacity(0.1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            if showCustomDuration {
                customDurationSection
            }
        }
    }

    private func durationButton(_ minutes: Int) -> some View {
        let selected = selectedMinutes == minutes

        return Button {
            selectedMinutes = minutes
            showCustomDuration = false
        } label: {
            Text(durationLabel(minutes))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    selected ? Color.white : Color.primary
                )
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            selected
                                ? Color.accentColor
                                : Color.secondary.opacity(0.1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var customDurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(
                "Hours: \(customHours)",
                value: $customHours,
                in: 0...168
            )

            Stepper(
                "Minutes: \(customMinutes)",
                value: $customMinutes,
                in: 0...59
            )

            Button("Use Custom Duration") {
                selectedMinutes =
                    customHours * 60 + customMinutes

                showCustomDuration = false
            }
            .disabled(
                customHours == 0 && customMinutes == 0
            )
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Session extension

    private var extensionSection: some View {
        HStack(spacing: 8) {
            Button("+15 min") {
                manager.extend(by: 15 * 60)
            }
            .frame(maxWidth: .infinity)

            Button("+30 min") {
                manager.extend(by: 30 * 60)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $manager.allowDisplaySleep) {
                Label(
                    "Allow display sleep",
                    systemImage: "display"
                )
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if battery.hasBattery {
                Toggle(isOn: $battery.pauseOnLowBattery) {
                    Label(
                        "Battery protection",
                        systemImage: "battery.100"
                    )
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .font(.system(size: 12))
    }

    // MARK: - Error

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                message,
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.red)

            Button("Retry") {
                manager.retry()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 8) {
            if manager.isPausedManually && manager.wantsAwake {
                primaryButton("Resume KeepAwake") {
                    manager.resume()
                }
            } else if manager.wantsAwake &&
                        !manager.isPausedManually {
                Button {
                    manager.pause()
                } label: {
                    Text("Pause KeepAwake")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else {
                primaryButton(
                    "Start · \(durationLabel(selectedMinutes))"
                ) {
                    startSession()
                }
            }

            if manager.isManualActive {
                Button("Restart with Selected Duration") {
                    startSession()
                }
                .font(.caption)

                Button("End Manual Session") {
                    manager.deactivate()
                }
                .font(.caption)
            }

            if manager.wantsAwake {
                Button("Stop All Activity") {
                    manager.stopAll()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    private func primaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(HotKey.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                manager.stopAll()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func startSession() {
        if selectedMinutes == 0 {
            manager.activate()
        } else {
            manager.activate(
                for: TimeInterval(selectedMinutes * 60)
            )
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes == 0 {
            return "∞"
        }

        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        return remainder == 0
            ? "\(hours)h"
            : "\(hours)h \(remainder)m"
    }

    private var statusColor: Color {
        switch manager.state {
        case .active:
            return .green

        case .pausedManually, .pausedLowBattery:
            return .orange

        case .failed:
            return .red

        case .inactive:
            return .secondary
        }
    }

    private var statusIcon: String {
        switch manager.state {
        case .active, .inactive:
            return "power"

        case .pausedManually, .pausedLowBattery:
            return "pause.fill"

        case .failed:
            return "exclamationmark"
        }
    }
}