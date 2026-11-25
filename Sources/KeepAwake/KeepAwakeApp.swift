import SwiftUI
import AppKit

@main
@MainActor
struct KeepAwakeApp: App {
    @StateObject private var sleepManager: SleepManager
    @StateObject private var appWatcher: AppWatcher
    @StateObject private var batteryMonitor: BatteryMonitor
    @StateObject private var hotKey: HotKey
    @StateObject private var schedule: ScheduleManager
    @StateObject private var loginItem = LoginItem()

    init() {
        let manager = SleepManager()

        _sleepManager = StateObject(
            wrappedValue: manager
        )

        _appWatcher = StateObject(
            wrappedValue: AppWatcher(
                sleepManager: manager
            )
        )

        _batteryMonitor = StateObject(
            wrappedValue: BatteryMonitor(
                sleepManager: manager
            )
        )

        _hotKey = StateObject(
            wrappedValue: HotKey(
                sleepManager: manager
            )
        )

        _schedule = StateObject(
            wrappedValue: ScheduleManager(
                sleepManager: manager
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                manager: sleepManager,
                battery: batteryMonitor
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)

                if sleepManager.isActive,
                   let remaining = sleepManager.remainingText {
                    Text(remaining)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("KeepAwake Settings", id: "settings") {
            SettingsView(
                manager: sleepManager,
                watcher: appWatcher,
                battery: batteryMonitor,
                hotKey: hotKey,
                schedule: schedule,
                loginItem: loginItem
            )
        }
        .defaultSize(width: 560, height: 440)
        .windowResizability(.contentSize)
    }

    private var menuBarIcon: String {
        switch sleepManager.state {
        case .active:
            return "cup.and.saucer.fill"

        case .pausedManually, .pausedLowBattery:
            return "pause.circle"

        case .failed:
            return "exclamationmark.circle"

        case .inactive:
            return "cup.and.saucer"
        }
    }
}