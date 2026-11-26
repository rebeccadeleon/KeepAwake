import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: SleepManager
    @ObservedObject var watcher: AppWatcher
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var hotKey: HotKey
    @ObservedObject var schedule: ScheduleManager
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var visibility: VisibilityManager

    @ObservedObject var downloads: DownloadManager
    @ObservedObject var assertions: AssertionMonitor
    @ObservedObject var electricity: ElectricityPriceManager
    @ObservedObject var websites: WebsiteMonitor
    @ObservedObject var reports: ReportManager
    @State private var searchText = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            applicationsTab
                .tabItem {
                    Label("Applications", systemImage: "app")
                }

            scheduleTab
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            DownloadSettingsView(
                manager: downloads
            )
            .tabItem {
                Label(
                    "Downloads",
                    systemImage: "arrow.down.circle"
                )
            }

            ElectricitySettingsView(
                manager: electricity
            )
            .tabItem {
                Label(
                    "Energy",
                    systemImage: "bolt.circle"
                )
            }

            WebsiteSettingsView(
                manager: websites
            )
            .tabItem {
                Label(
                    "Websites",
                    systemImage: "globe"
                )
            }

            AssertionSettingsView(
                monitor: assertions
            )
            .tabItem {
                Label(
                    "Assertions",
                    systemImage: "waveform.path"
                )
            }

            ReportSettingsView(
                manager: reports
            )
            .tabItem {
                Label(
                    "Reports",
                    systemImage: "doc.text"
                )
            }

            appearanceTab
                .tabItem {
                    Label(
                        "Appearance",
                        systemImage: "macwindow"
                    )
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(12)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch KeepAwake at login",
                    isOn: Binding(
                        get: {
                            loginItem.isEnabled
                        },
                        set: {
                            loginItem.setEnabled($0)
                        }
                    )
                )
            }

            Section("Power management") {
                Toggle(
                    "Allow display sleep",
                    isOn: $manager.allowDisplaySleep
                )

                if battery.hasBattery {
                    Toggle(
                        "Pause when battery is at or below \(BatteryMonitor.threshold)%",
                        isOn: $battery.pauseOnLowBattery
                    )
                }

                Text(
                    "Allowing the display to sleep reduces power consumption while keeping the system awake."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Keyboard shortcut") {
                Toggle(
                    "Enable global shortcut",
                    isOn: $hotKey.isEnabled
                )

                HStack {
                    Text("Toggle KeepAwake")

                    Spacer()

                    Text(HotKey.displayName)
                        .font(.system(
                            size: 13,
                            design: .monospaced
                        ))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    Color.secondary.opacity(0.1)
                                )
                        )
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Applications

    private var applicationsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application Rules")
                .font(.headline)

            Text(
                "Keep your Mac awake automatically while selected applications are running."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    "Search applications",
                    text: $searchText
                )
                .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
            )

            List(filteredApps) { app in
                Toggle(
                    isOn: Binding(
                        get: {
                            watcher.isWatched(app)
                        },
                        set: {
                            watcher.setWatched(app, $0)
                        }
                    )
                ) {
                    HStack(spacing: 10) {
                        applicationIcon(app.id)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)

                            Text(app.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if watcher.runningApps.contains(
                            where: { $0.id == app.id }
                        ) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                                .help("Running")
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 3)
            }
            .listStyle(.inset)

            Text("\(watcher.watched.count) selected applications")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var filteredApps: [WatchedApp] {
        guard !searchText.isEmpty else {
            return watcher.menuApps
        }

        return watcher.menuApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func applicationIcon(
        _ bundleID: String
    ) -> some View {
        Group {
            if let url = NSWorkspace.shared
                .urlForApplication(
                    withBundleIdentifier: bundleID
                ) {
                Image(
                    nsImage: NSWorkspace.shared.icon(
                        forFile: url.path
                    )
                )
                .resizable()
                .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Schedule

    private var scheduleTab: some View {
        Form {
            Section("Automatic schedule") {
                Toggle(
                    "Enable schedule",
                    isOn: $schedule.isEnabled
                )

                Picker(
                    "Days",
                    selection: $schedule.days
                ) {
                    ForEach(
                        ScheduleManager.Days.allCases
                    ) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
                .disabled(!schedule.isEnabled)

                Picker(
                    "From",
                    selection: $schedule.startHour
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(
                            ScheduleManager.hourLabel(hour)
                        )
                        .tag(hour)
                    }
                }
                .disabled(!schedule.isEnabled)

                Picker(
                    "Until",
                    selection: $schedule.endHour
                ) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(
                            ScheduleManager.hourLabel(hour)
                        )
                        .tag(hour)
                    }
                }
                .disabled(!schedule.isEnabled)
            }

            Section("Status") {
                if let end = manager.scheduleEndText {
                    Label(
                        "Schedule active until \(end)",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Schedule is not currently active",
                        systemImage: "clock"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Text(
                "Schedules use your Mac's local time. Global pause overrides automatic activation."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("Application visibility") {
                Toggle(
                    isOn: Binding(
                        get: {
                            visibility.showInDock
                        },
                        set: {
                            visibility.setShowInDock($0)
                        }
                    )
                ) {
                    Label(
                        "Show in Dock",
                        systemImage: "dock.rectangle"
                    )
                }

                Toggle(
                    isOn: Binding(
                        get: {
                            visibility.showInMenuBar
                        },
                        set: {
                            visibility.setShowInMenuBar($0)
                        }
                    )
                ) {
                    Label(
                        "Show in menu bar",
                        systemImage: "menubar.rectangle"
                    )
                }
            }

            Section("Startup Behavior") {
                Toggle(
                    "Start hidden",
                    isOn: $visibility.startHidden
                )

                Text(
                    "Launch KeepAwake without showing its Dock " +
                    "or menu bar icon. Press " +
                    "⌃⌥⌘H to restore visibility."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Recovery shortcut") {
                HStack {
                    Text("Toggle application visibility")

                    Spacer()

                    Text(HotKey.visibilityDisplayName)
                        .font(.system(
                            size: 13,
                            design: .monospaced
                        ))
                        .padding(6)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    Color.secondary.opacity(0.08)
                                )
                        }
                }

                if hotKey.isVisibilityRegistered {
                    Label(
                        "Shortcut registered",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .font(.caption)
                } else {
                    Label(
                        "Shortcut unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)

                    Button("Retry Registration") {
                        hotKey.retryVisibilityRegistration()
                    }
                }

                if let error = hotKey.registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Background operation") {
                Text(
                    "KeepAwake continues running when its " +
                    "Dock and menu bar icons are hidden."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    "Press \(HotKey.visibilityDisplayName) " +
                    "to restore application visibility."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Hide KeepAwake") {
                    visibility.hide()
                }
                .disabled(!visibility.canHide)
            }

            if let error = visibility.visibilityError {
                Section {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            Text("KeepAwake")
                .font(.system(size: 24, weight: .semibold))

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            Text(
                "A lightweight power and sleep management utility for macOS."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 300)

            Divider()
                .frame(width: 240)
                .padding(.vertical, 8)

            Text("Built with SwiftUI and IOKit")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }
}