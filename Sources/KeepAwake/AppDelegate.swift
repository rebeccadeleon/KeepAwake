import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    private let sleepManager = SleepManager()
    private let visibility = VisibilityManager()
    private var downloadManager: DownloadManager!
    private var electricityManager: ElectricityPriceManager!
    private var websiteMonitor: WebsiteMonitor!
    private var assertionMonitor: AssertionMonitor!
    private var reportManager: ReportManager!
    private var activityManager: ActivityHistoryManager!

    private var appWatcher: AppWatcher!
    private var batteryMonitor: BatteryMonitor!
    private var hotKey: HotKey!
    private var schedule: ScheduleManager!
    private var loginItem: LoginItem!

    // MARK: - Interface

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastPopoverHeight: CGFloat = 0
    private var popoverResizeTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    private var visibilityUpdateTask: Task<Void, Never>?

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        appWatcher = AppWatcher(
            sleepManager: sleepManager
        )

        batteryMonitor = BatteryMonitor(
            sleepManager: sleepManager
        )

        schedule = ScheduleManager(
            sleepManager: sleepManager
        )

        loginItem = LoginItem()

        hotKey = HotKey(
            sleepManager: sleepManager,
            visibilityManager: visibility
        )

        downloadManager = DownloadManager(
            sleepManager: sleepManager
        )

        electricityManager = ElectricityPriceManager(
            sleepManager: sleepManager
        )

        websiteMonitor = WebsiteMonitor(
            sleepManager: sleepManager
        )

        assertionMonitor = AssertionMonitor()

        activityManager = ActivityHistoryManager(
            sleepManager: sleepManager,
            assertionMonitor: assertionMonitor,
            downloadManager: downloadManager
        )

        reportManager = ReportManager(
            sleep: sleepManager,
            battery: batteryMonitor,
            watcher: appWatcher,
            schedule: schedule,
            assertions: assertionMonitor,
            downloads: downloadManager,
            electricity: electricityManager,
            websites: websiteMonitor,
            activity: activityManager
        )

        createPopover()
        createStatusItem()
        observeSleepState()
        observeAssertionState()

        visibility.onVisibilityChanged = { [weak self] in
            self?.scheduleVisibilityUpdate()
        }

        configureApplicationMenu()

        if visibility.startHidden && visibility.canHide {
            visibility.hide()
        }
        applyVisibility()
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        activityManager?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()

        configuration.createsNewApplicationInstance = true
        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error = error {
                print("Failed to launch new instance: \(error)")
            }
        }

        return false
    }

    // MARK: - Status item

    private func createStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))

            button.sendAction(on: [.leftMouseUp])

            button.toolTip = "KeepAwake"
        }

        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        let symbol: String

        switch sleepManager.state {
        case .active:
            symbol = "cup.and.saucer.fill"

        case .pausedManually, .pausedLowBattery:
            symbol = "pause.circle"

        case .failed:
            symbol = "exclamationmark.circle"

        case .inactive:
            symbol = assertionMonitor.hasExternalSleepBlockers
                ? "cup.and.saucer.badge.exclamationmark"
                : "cup.and.saucer"
        }

        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "KeepAwake"
        ) ?? NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: "KeepAwake"
        )

        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageLeading

        if sleepManager.isActive,
           let remaining = sleepManager.remainingText {
            button.title = " \(remaining)"
        } else {
            button.title = ""
        }

        if assertionMonitor.hasExternalSleepBlockers {
            button.toolTip =
                sleepManager.statusText +
                "\nExternal sleep blockers: " +
                "\(assertionMonitor.externalBlockingProcesses.count)"
        } else {
            button.toolTip = sleepManager.statusText
        }
    }

    private func observeAssertionState() {
        assertionMonitor.$assertions
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func observeSleepState() {
        sleepManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Popover

    private func createPopover() {
        let view = MenuBarView(
            manager: sleepManager,
            battery: batteryMonitor,
            visibility: visibility,
            assertionMonitor: assertionMonitor,

            onOpenSettings: { [weak self] in
                self?.openSettings()
            },

            onHeightChange: { [weak self] height in
                self?.resizePopover(to: height)
            },

            onGenerateReport: { [weak self] in
                self?.generateQuickReport()
            }
        )

        let controller = NSHostingController(
            rootView: view
        )

        let popover = NSPopover()

        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

        self.popover = popover

        controller.view.layoutSubtreeIfNeeded()

        let fittingSize = controller.view.fittingSize

        let initialHeight = fittingSize.height > 0
            ? ceil(fittingSize.height)
            : 420

        popover.contentSize = NSSize(
            width: 320,
            height: initialHeight
        )

        lastPopoverHeight = initialHeight
    }

    private func resizePopover(to height: CGFloat) {
        guard height.isFinite, height > 0 else {
            return
        }

        let targetHeight = ceil(height)

        guard abs(
            lastPopoverHeight - targetHeight
        ) > 1 else {
            return
        }

        popoverResizeTask?.cancel()

        popoverResizeTask = Task {
            @MainActor [weak self] in

            await Task.yield()

            guard !Task.isCancelled,
                let self,
                let popover = self.popover else {
                return
            }

            self.lastPopoverHeight = targetHeight

            popover.contentSize = NSSize(
                width: 320,
                height: targetHeight
            )
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let popover,
            let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        if let controller = popover.contentViewController {
            controller.view.layoutSubtreeIfNeeded()

            let height = controller.view.fittingSize.height

            if height.isFinite, height > 0 {
                let targetHeight = ceil(height)

                popover.contentSize = NSSize(
                    width: 320,
                    height: targetHeight
                )

                lastPopoverHeight = targetHeight
            }
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )

        popover.contentViewController?
            .view.window?
            .makeKey()
    }

    private func closePopover() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
    }

    // MARK: - Visibility

    private func scheduleVisibilityUpdate() {
        visibilityUpdateTask?.cancel()

        visibilityUpdateTask = Task {
            @MainActor [weak self] in

            await Task.yield()

            guard !Task.isCancelled else {
                return
            }

            self?.applyVisibility()
        }
    }

    private func applyVisibility() {
        // Close the popover before removing its anchor.
        if !visibility.isMenuBarVisible {
            closePopover()
        }

        if visibility.isHidden {
            settingsWindow?.orderOut(nil)
        }

        // Keep the status item alive.
        // Only change its visibility.
        statusItem?.isVisible =
            visibility.isMenuBarVisible

        let policy: NSApplication.ActivationPolicy =
            visibility.isDockVisible
                ? .regular
                : .accessory

        if NSApp.activationPolicy() != policy {
            let success = NSApp.setActivationPolicy(
                policy
            )

            if !success {
                NSLog(
                    "KeepAwake: activation policy change failed"
                )
            }
        }

        updateStatusItem()
    }

    // MARK: - Settings

    @objc
    private func openSettings() {
        closePopover()

        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            manager: sleepManager,
            watcher: appWatcher,
            battery: batteryMonitor,
            hotKey: hotKey,
            schedule: schedule,
            loginItem: loginItem,
            visibility: visibility,
            downloads: downloadManager,
            assertions: assertionMonitor,
            electricity: electricityManager,
            websites: websiteMonitor,
            reports: reportManager,
            activity: activityManager
        )

        let controller = NSHostingController(
            rootView: view
        )

        let window: NSWindow = NSWindow(
            contentViewController: controller
        )


        window.title = "KeepAwake Settings"

        window.styleMask = NSWindow.StyleMask([
            .titled,
            .closable,
            .miniaturizable,
            .resizable
        ])

        window.setContentSize(
            NSSize(
                width: 820,
                height: 540
            )
        )

        window.minSize = NSSize(
            width: 720,
            height: 500
        )

        window.styleMask.insert(.resizable)

        window.isReleasedWhenClosed = false

        window.center()

        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)

        window.makeKeyAndOrderFront(nil)
    }

    private func generateQuickReport() {
        closePopover()

        NSApp.activate(
            ignoringOtherApps: true
        )

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard !self.reportManager.isGenerating else {
                return
            }

            await self.reportManager.generate()
            await self.reportManager.save()
        }
    }

    // MARK: - Application menu

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(
            title: "KeepAwake"
        )

        appMenuItem.submenu = appMenu

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )

        settingsItem.target = self

        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide KeepAwake",
            action: #selector(hideApplication),
            keyEquivalent: ""
        )

        hideItem.target = self

        appMenu.addItem(hideItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit KeepAwake",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )

        quitItem.target = self

        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc
    private func hideApplication() {
        visibility.hide()
    }

    @objc
    private func quitApplication() {
        sleepManager.stopAll()
        NSApp.terminate(nil)
    }
}