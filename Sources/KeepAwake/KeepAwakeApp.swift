import SwiftUI

@main
struct KeepAwakeApp: App {
    @StateObject private var sleepManager = SleepManager()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(manager: sleepManager)
        } label: {
            Image(systemName: sleepManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var manager: SleepManager

    var body: some View {
        Text(statusText)

        Divider()

        if manager.isActive {
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

        Button("Quit Keep Awake") {
            manager.deactivate()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        guard manager.isActive else {
            return "Keep Awake is off"
        }
        if let endDate = manager.endDate {
            let time = endDate.formatted(date: .omitted, time: .shortened)
            return "On until \(time)"
        }
        return "On until you turn it off"
    }
}
