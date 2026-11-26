import SwiftUI
import AppKit

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(
        value: inout CGFloat,
        nextValue: () -> CGFloat
    ) {
        value = max(value, nextValue())
    }
}

struct MenuBarView: View {
    @ObservedObject var manager: SleepManager
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var visibility: VisibilityManager

    let onOpenSettings: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @AppStorage("selectedSessionMinutes")
    private var selectedMinutes = 60

    @State private var customHours = 1
    @State private var customMinutes = 0
    @State private var showCustomDuration = false

    @Environment(\.colorScheme)
    private var colorScheme

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.13, blue: 0.15)
            : Color.white
    }

    private var secondaryBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.07)
    }

    private let durations = [
        15, 30, 60, 120, 240, 480, 0
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(14)

            Divider()

            VStack(spacing: 12) {
                statusSection

                if !manager.automaticReasons.isEmpty {
                    automaticRulesSection
                }

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
            }
            .padding(14)
            .frame(maxWidth: .infinity)

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(panelBackground)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ContentHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
        .onPreferenceChange(
            ContentHeightPreferenceKey.self
        ) { height in
            guard height > 0 else {
                return
            }

            onHeightChange(height)
        }
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
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var automaticRulesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ACTIVE RULES")
                .font(.system(
                    size: 10,
                    weight: .semibold
                ))
                .foregroundStyle(.secondary)

            ForEach(
                AutomaticAwakeReason.allCases,
                id: \.self
            ) { reason in
                if let description =
                    manager.automaticReasons[reason] {

                    HStack(spacing: 8) {
                        Image(systemName: ruleIcon(reason))
                            .foregroundStyle(ruleColor(reason))
                            .frame(width: 20)

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(ruleTitle(reason))
                                .font(.system(
                                    size: 12,
                                    weight: .medium
                                ))

                            Text(description)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(
                            systemName: "checkmark.circle.fill"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(
                            manager.isActive
                                ? Color.green
                                : Color.secondary
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(
            secondaryBackground,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func ruleIcon(
        _ reason: AutomaticAwakeReason
    ) -> String {
        switch reason {
        case .downloads:
            return "arrow.down.circle"

        case .electricity:
            return "bolt.circle"

        case .websiteMonitoring:
            return "globe"
        }
    }

    private func ruleTitle(
        _ reason: AutomaticAwakeReason
    ) -> String {
        switch reason {
        case .downloads:
            return "Downloads"

        case .electricity:
            return "Electricity"

        case .websiteMonitoring:
            return "Websites"
        }
    }

    private func ruleColor(
        _ reason: AutomaticAwakeReason
    ) -> Color {
        switch reason {
        case .downloads:
            return .blue

        case .electricity:
            return .orange

        case .websiteMonitoring:
            return .green
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 5) {
            Button {
                if !manager.wantsAwake {
                    startSession()
                } else {
                    manager.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.06))

                    Circle()
                        .strokeBorder(
                            statusColor.opacity(0.35),
                            lineWidth: 1.5
                        )

                    Image(systemName: statusIcon)
                        .font(.system(
                            size: 28,
                            weight: .medium
                        ))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .help("Toggle KeepAwake")

            Text(manager.statusText)
                .font(.system(
                    size: 15,
                    weight: .semibold
                ))

            if let remaining = manager.remainingText {
                Text(remaining)
                    .font(.system(
                        size: 24,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(statusColor)
            }

            Text(manager.reasonText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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
                                .fill(secondaryBackground)
                        )
                }
                .buttonStyle(.plain)
            }

            if showCustomDuration {
                customDurationSection
            }
        }
    }

    private func durationButton(
        _ minutes: Int
    ) -> some View {
        let selected = selectedMinutes == minutes

        return Button {
            selectedMinutes = minutes
            showCustomDuration = false
        } label: {
            Text(durationLabel(minutes))
                .font(.system(
                    size: 12,
                    weight: .medium
                ))
                .foregroundStyle(
                    selected ? Color.white : Color.primary
                )
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            selected
                                ? Color.accentColor
                                : secondaryBackground
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            selected ? Color.clear : borderColor,
                            lineWidth: 1
                        )
                }
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
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text("Allow display sleep")

                Spacer()

                Toggle(
                    "",
                    isOn: $manager.allowDisplaySleep
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Allow display sleep")
            }

            if battery.hasBattery {
                HStack(spacing: 8) {
                    Image(systemName: "battery.100")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    Text("Battery protection")

                    Spacer()

                    Toggle(
                        "",
                        isOn: $battery.pauseOnLowBattery
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Battery protection")
                }
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 6) {
            if manager.wantsAwake {
                HStack(spacing: 8) {
                    if manager.isPausedManually {
                        actionButton(
                            "Resume",
                            icon: "play.fill",
                            color: .accentColor
                        ) {
                            manager.resume()
                        }
                    } else {
                        actionButton(
                            "Pause",
                            icon: "pause.fill",
                            color: .primary
                        ) {
                            manager.pause()
                        }
                    }

                    actionButton(
                        "Stop",
                        icon: "stop.fill",
                        color: .red
                    ) {
                        manager.stopAll()
                    }
                }

                if manager.isManualActive {
                    Menu {
                        Button("Restart with Selected Duration") {
                            startSession()
                        }

                        Button("End Manual Session") {
                            manager.deactivate()
                        }
                    } label: {
                        Text("Session Options")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else {
                primaryButton(
                    "Start · \(durationLabel(selectedMinutes))"
                ) {
                    startSession()
                }

                if manager.isPausedManually {
                    Button("Resume Automatic Rules") {
                        manager.resume()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))

                Text(title)
                    .font(.system(
                        size: 12,
                        weight: .medium
                    ))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(secondaryBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        borderColor,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(
                    size: 13,
                    weight: .semibold
                ))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(HotKey.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("Toggle sleep prevention")

            Spacer()

            Button {
                visibility.hide()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))

                    Text("Hide")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!visibility.canHide)
            .help(
                "Hide KeepAwake · " +
                HotKey.visibilityDisplayName
            )

            Divider()
                .frame(height: 12)

            Button("Quit") {
                manager.stopAll()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
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