import SwiftUI

@main
struct KeepAwakeApp: App {
    @StateObject private var sleepManager: SleepManager
    @StateObject private var appWatcher: AppWatcher
    @StateObject private var batteryMonitor: BatteryMonitor
    @StateObject private var hotKey: HotKey
    @StateObject private var loginItem = LoginItem()

    init() {
        let manager = SleepManager()
        _sleepManager = StateObject(wrappedValue: manager)
        _appWatcher = StateObject(wrappedValue: AppWatcher(sleepManager: manager))
        _batteryMonitor = StateObject(wrappedValue: BatteryMonitor(sleepManager: manager))
        _hotKey = StateObject(wrappedValue: HotKey(sleepManager: manager))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                manager: sleepManager,
                watcher: appWatcher,
                battery: batteryMonitor,
                hotKey: hotKey,
                loginItem: loginItem
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sleepManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                if sleepManager.isActive, let remaining = sleepManager.remainingText {
                    Text(remaining)
                }
            }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var manager: SleepManager
    @ObservedObject var watcher: AppWatcher
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var hotKey: HotKey
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Text(statusText)

        Divider()

        if manager.isManualActive {
            Button("Turn Off") {
                manager.deactivate()
            }
        }

        Button("Keep Awake Until I Turn It Off") {
            manager.activate()
        }
        Button("Keep Awake for 30 Minutes") {
            manager.activate(for: 30 * 60)
        }
        Button("Keep Awake for 1 Hour") {
            manager.activate(for: 60 * 60)
        }
        Button("Keep Awake for 2 Hours") {
            manager.activate(for: 2 * 60 * 60)
        }

        Divider()

        Menu("Keep Awake While Running") {
            ForEach(watcher.menuApps) { app in
                Toggle(app.name, isOn: Binding(
                    get: { watcher.isWatched(app) },
                    set: { watcher.setWatched(app, $0) }
                ))
            }
        }

        Toggle("Allow Display to Sleep", isOn: $manager.allowDisplaySleep)

        if battery.hasBattery {
            Toggle(
                "Pause When Battery Is Below \(BatteryMonitor.threshold)%",
                isOn: $battery.pauseOnLowBattery
            )
        }
        Toggle("Toggle with \(HotKey.displayName)", isOn: $hotKey.isEnabled)

        Toggle("Launch at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))

        Divider()

        Button("Quit Keep Awake") {
            manager.deactivate()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        if manager.wantsAwake, manager.isPausedForLowBattery {
            return "Paused: battery is low"
        }
        if manager.isManualActive {
            if let endDate = manager.endDate {
                let time = endDate.formatted(date: .omitted, time: .shortened)
                return "On until \(time)"
            }
            return "On until you turn it off"
        }
        if let first = manager.triggeringApps.first {
            let others = manager.triggeringApps.count - 1
            if others == 0 {
                return "On while \(first) is running"
            }
            return "On while \(first) and \(others) more are running"
        }
        return "Keep Awake is off"
    }
}