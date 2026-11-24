import Foundation
import IOKit.ps

/// Checks the battery every 30 seconds and pauses Keep Awake when the Mac
/// is on battery power and the charge is low.
@MainActor
final class BatteryMonitor: ObservableObject {
    /// Pause at or below this charge percentage.
    static let threshold = 20

    private static let defaultsKey = "pauseOnLowBattery"

    /// Whether the low battery pause is switched on. Defaults to on.
    @Published var pauseOnLowBattery =
        (UserDefaults.standard.object(forKey: BatteryMonitor.defaultsKey) as? Bool) ?? true {
        didSet {
            guard oldValue != pauseOnLowBattery else { return }
            UserDefaults.standard.set(pauseOnLowBattery, forKey: Self.defaultsKey)
            check()
        }
    }

    /// False on Macs without a battery, such as a Mac mini.
    @Published private(set) var hasBattery = false

    private let sleepManager: SleepManager
    private var timer: Timer?

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager

        let newTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer

        check()
    }

    private func check() {
        let battery = Self.readBattery()

        let found = battery != nil
        if found != hasBattery {
            hasBattery = found
        }

        var isLow = false
        if pauseOnLowBattery, let battery {
            isLow = battery.onBattery && battery.percent <= Self.threshold
        }
        sleepManager.setPausedForLowBattery(isLow)
    }

    /// Reads the internal battery's charge, or returns nil if there is none.
    private static func readBattery() -> (percent: Int, onBattery: Bool)? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }

            let onBattery = info[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return (current * 100 / maximum, onBattery)
        }
        return nil
    }
}