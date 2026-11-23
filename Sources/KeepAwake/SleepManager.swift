import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion that stops the Mac (and its display) from going
/// to sleep while the user is idle. Releasing the assertion restores the
/// normal Energy settings.
@MainActor
final class SleepManager: ObservableObject {
    /// True while the Mac is being kept awake.
    @Published private(set) var isActive = false

    /// When the current session ends, or nil if it runs until turned off.
    @Published private(set) var endDate: Date?

    private var assertionID = IOPMAssertionID(0)
    private var timer: Timer?

    /// Starts keeping the Mac awake.
    /// - Parameter duration: Seconds to stay awake, or nil for "until turned off".
    func activate(for duration: TimeInterval? = nil) {
        deactivate()

        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Keep Awake is turned on" as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            NSLog("KeepAwake: could not create power assertion (error \(result))")
            return
        }

        assertionID = newID
        isActive = true

        if let duration {
            endDate = Date().addingTimeInterval(duration)
            let newTimer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.deactivate()
                }
            }
            // .common keeps the timer firing even while the menu is open.
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }
    }

    /// Stops keeping the Mac awake.
    func deactivate() {
        timer?.invalidate()
        timer = nil

        if isActive {
            IOPMAssertionRelease(assertionID)
        }
        assertionID = IOPMAssertionID(0)
        isActive = false
        endDate = nil
    }
}
