import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion that stops the Mac from going to sleep while the
/// user is idle. The Mac is kept awake while a manual session is on, or
/// while one of the user's chosen apps is running.
@MainActor
final class SleepManager: ObservableObject {
    private static let allowDisplaySleepKey = "allowDisplaySleep"

    /// True while a session the user started from the menu is on.
    @Published private(set) var isManualActive = false

    /// When the manual session ends, or nil if it runs until turned off.
    @Published private(set) var endDate: Date?

    /// Time left in a timed session, such as "42m" or "1h 5m". Nil otherwise.
    @Published private(set) var remainingText: String?

    /// True while the low battery pause is in effect.
    @Published private(set) var isPausedForLowBattery = false

    /// When the schedule is keeping the Mac awake, the time it ends, such
    /// as "18:00". Nil when the schedule is not in effect.
    @Published private(set) var scheduleEndText: String?

    /// Names of chosen apps that are running now.
    @Published private(set) var triggeringApps: [String] = []

    /// When true, the display may turn off while the Mac itself stays awake.
    @Published var allowDisplaySleep = UserDefaults.standard.bool(forKey: SleepManager.allowDisplaySleepKey) {
        didSet {
            guard oldValue != allowDisplaySleep else { return }
            UserDefaults.standard.set(allowDisplaySleep, forKey: Self.allowDisplaySleepKey)
            // Swap the assertion for the other kind if one is held now.
            if holdsAssertion {
                releaseAssertion()
                updateAssertion()
            }
        }
    }

    /// True when the user wants the Mac awake: a manual session is on, a
    /// chosen app is running, or the schedule is in effect.
    var wantsAwake: Bool {
        isManualActive || !triggeringApps.isEmpty || scheduleEndText != nil
    }

    /// True while the Mac is actually being kept awake.
    var isActive: Bool {
        wantsAwake && !isPausedForLowBattery
    }

    private var assertionID = IOPMAssertionID(0)
    private var holdsAssertion = false
    private var timer: Timer?

    /// Starts a manual session.
    /// - Parameter duration: Seconds to stay awake, or nil for "until turned off".
    func activate(for duration: TimeInterval? = nil) {
        stopTimer()
        isManualActive = true

        if let duration {
            endDate = Date().addingTimeInterval(duration)
            updateRemainingText()

            let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
            // .common keeps the timer firing even while the menu is open.
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }

        updateAssertion()
    }

    /// Ends the manual session. The Mac stays awake if a chosen app is running.
    func deactivate() {
        stopTimer()
        isManualActive = false
        updateAssertion()
    }

    /// Called by BatteryMonitor when the low battery state changes.
    func setPausedForLowBattery(_ paused: Bool) {
        if paused != isPausedForLowBattery {
            isPausedForLowBattery = paused
        }
        updateAssertion()
    }

    /// Called by ScheduleManager. Pass the end time while inside the
    /// schedule, or nil when outside it.
    func setSchedule(endText: String?) {
        if endText != scheduleEndText {
            scheduleEndText = endText
        }
        updateAssertion()
    }

    /// Called by AppWatcher whenever the set of running chosen apps changes.
    func setTriggeringApps(_ names: [String]) {
        if names != triggeringApps {
            triggeringApps = names
        }
        updateAssertion()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingText = nil
    }

    /// Creates or releases the power assertion to match `isActive`.
    private func updateAssertion() {
        if isActive, !holdsAssertion {
            // "System sleep" keeps the Mac awake but lets the display turn
            // off; "display sleep" keeps both awake.
            let type = allowDisplaySleep
                ? kIOPMAssertionTypePreventUserIdleSystemSleep
                : kIOPMAssertionTypePreventUserIdleDisplaySleep

            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Keep Awake is turned on" as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
                holdsAssertion = true
            } else {
                NSLog("KeepAwake: could not create power assertion (error \(result))")
            }
        } else if !isActive, holdsAssertion {
            releaseAssertion()
        }
    }

    private func releaseAssertion() {
        guard holdsAssertion else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        holdsAssertion = false
    }

    private func tick() {
        guard let endDate else { return }
        if Date() >= endDate {
            deactivate()
        } else {
            updateRemainingText()
        }
    }

    private func updateRemainingText() {
        guard let endDate else { return }
        let text = Self.format(endDate.timeIntervalSinceNow)
        // Publish only when the text changes, so the menu bar redraws
        // once a minute instead of once a second.
        if text != remainingText {
            remainingText = text
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}