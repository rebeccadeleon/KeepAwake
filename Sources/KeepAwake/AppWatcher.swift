import AppKit

struct WatchedApp: Identifiable, Hashable {
    let id: String      // bundle identifier
    let name: String
}

/// Watches which apps are running and tells SleepManager when one of the
/// apps the user chose is open.
@MainActor
final class AppWatcher: ObservableObject {
    /// Apps the user chose, as bundle identifier -> display name.
    @Published private(set) var watched: [String: String]

    /// Ordinary (Dock) apps that are running right now.
    @Published private(set) var runningApps: [WatchedApp] = []

    private let sleepManager: SleepManager
    private let defaultsKey = "watchedApps"
    private var observers: [NSObjectProtocol] = []

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager
        self.watched = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]

        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The app that just quit can still be in the running list for a
            // moment, so leave it out explicitly.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            Task { @MainActor in
                self?.refresh(excludingPID: pid)
            }
        })

        refresh()
    }

    /// Apps to show in the menu: everything running, plus chosen apps that
    /// are not running at the moment.
    var menuApps: [WatchedApp] {
        var list = runningApps
        let runningIDs = Set(runningApps.map(\.id))
        for (id, name) in watched where !runningIDs.contains(id) {
            list.append(WatchedApp(id: id, name: name))
        }
        return list.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func isWatched(_ app: WatchedApp) -> Bool {
        watched[app.id] != nil
    }

    func setWatched(_ app: WatchedApp, _ isOn: Bool) {
        if isOn {
            watched[app.id] = app.name
        } else {
            watched[app.id] = nil
        }
        UserDefaults.standard.set(watched, forKey: defaultsKey)
        refresh()
    }

    private func refresh(excludingPID: pid_t? = nil) {
        let ownID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var list: [WatchedApp] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != excludingPID,
                  let id = app.bundleIdentifier,
                  id != ownID,
                  seen.insert(id).inserted
            else { continue }
            list.append(WatchedApp(id: id, name: app.localizedName ?? id))
        }

        list.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        runningApps = list

        let triggering = list.filter { watched[$0.id] != nil }.map(\.name)
        sleepManager.setTriggeringApps(triggering)
    }
}