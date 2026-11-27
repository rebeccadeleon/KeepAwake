import Foundation
import Combine
import AppKit
import IOKit
import IOKit.ps

struct BatterySample: Identifiable, Codable {
    var id = UUID()
    let timestamp: Date
    let percentage: Int
    let onBattery: Bool
    let isCharging: Bool
}

struct BatteryInformation {
    let percentage: Int
    let onBattery: Bool
    let isCharging: Bool

    let timeToEmpty: Int?
    let timeToFull: Int?

    let cycleCount: Int?
    let healthPercentage: Double?

    var powerSource: String {
        onBattery ? "Battery" : "AC Adapter"
    }

    var chargingStatus: String {
        if isCharging {
            return "Charging"
        }

        if onBattery {
            return "Discharging"
        }

        if percentage >= 100 {
            return "Fully charged"
        }

        return "Not charging"
    }
}

@MainActor
final class BatteryMonitor: ObservableObject {
    static let threshold = 20

    private let defaults = UserDefaults.standard

    @Published var pauseOnLowBattery =
        UserDefaults.standard.object(
            forKey: "pauseOnLowBattery"
        ) as? Bool ?? true {
        didSet {
            defaults.set(
                pauseOnLowBattery,
                forKey: "pauseOnLowBattery"
            )
            check()
        }
    }

    @Published var pauseThreshold =
        UserDefaults.standard.object(
            forKey: "battery.pauseThreshold"
        ) as? Int ?? 20 {
        didSet {
            defaults.set(
                pauseThreshold,
                forKey: "battery.pauseThreshold"
            )
            check()
        }
    }

    @Published var resumeThreshold =
        UserDefaults.standard.object(
            forKey: "battery.resumeThreshold"
        ) as? Int ?? 30 {
        didSet {
            defaults.set(
                resumeThreshold,
                forKey: "battery.resumeThreshold"
            )
            check()
        }
    }

    @Published var acPowerOnly =
        UserDefaults.standard.bool(
            forKey: "battery.acPowerOnly"
        ) {
        didSet {
            defaults.set(
                acPowerOnly,
                forKey: "battery.acPowerOnly"
            )
            check()
        }
    }

    @Published private(set) var hasBattery = false

    @Published private(set) var information:
        BatteryInformation?

    @Published private(set) var history:
        [BatterySample] = []

    @Published private(set) var isProtectionActive = false

    @Published private(set) var protectionReason: String?

    @Published private(set) var lastUpdated: Date?

    private let sleepManager: SleepManager

    private var timer: Timer?
    private var notificationSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    private var lowBatteryLatched = false
    private var lastHistorySample: Date?

    private let historyKey = "battery.history"

    private let historyRetention: TimeInterval =
        7 * 24 * 3600

    private let historyInterval: TimeInterval = 300

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager

        loadHistory()
        observePowerChanges()
        observeSystemWake()
        startTimer()

        check()
    }

    // MARK: - Thresholds

    var effectivePauseThreshold: Int {
        min(50, max(5, pauseThreshold))
    }

    var effectiveResumeThreshold: Int {
        min(
            100,
            max(
                effectivePauseThreshold + 5,
                resumeThreshold
            )
        )
    }

    func setPauseThreshold(_ value: Int) {
        pauseThreshold = min(50, max(5, value))

        if resumeThreshold < pauseThreshold + 5 {
            resumeThreshold = pauseThreshold + 5
        }
    }

    func setResumeThreshold(_ value: Int) {
        resumeThreshold = min(
            100,
            max(
                effectivePauseThreshold + 5,
                value
            )
        )
    }

    // MARK: - Monitoring

    private func startTimer() {
        let newTimer = Timer(
            timeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.check()
            }
        }

        newTimer.tolerance = 10

        RunLoop.main.add(
            newTimer,
            forMode: .common
        )

        timer = newTimer
    }

    private func observePowerChanges() {
        let context = Unmanaged
            .passUnretained(self)
            .toOpaque()

        guard let source =
            IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else {
                        return
                    }

                    let monitor = Unmanaged<BatteryMonitor>
                        .fromOpaque(context)
                        .takeUnretainedValue()

                    Task { @MainActor [weak monitor] in
                        monitor?.check()
                    }
                },
                context
            )?.takeRetainedValue() else {
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )

        notificationSource = source
    }

    private func observeSystemWake() {
        NSWorkspace.shared.notificationCenter
            .publisher(
                for: NSWorkspace.didWakeNotification
            )
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.check()
                }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        check()
    }

    private func check() {
        let battery = Self.readBattery()

        information = battery
        hasBattery = battery != nil
        lastUpdated = Date()

        guard let battery else {
            lowBatteryLatched = false

            applyProtection(
                active: false,
                reason: nil
            )

            return
        }

        evaluateProtection(battery)
        recordHistory(battery)
    }

    // MARK: - Battery protection

    private func evaluateProtection(
        _ battery: BatteryInformation
    ) {
        if !pauseOnLowBattery || !battery.onBattery {
            lowBatteryLatched = false
        } else if lowBatteryLatched {
            if battery.percentage >=
                effectiveResumeThreshold {

                lowBatteryLatched = false
            }
        } else if battery.percentage <=
                    effectivePauseThreshold {

            lowBatteryLatched = true
        }

        if acPowerOnly && battery.onBattery {
            applyProtection(
                active: true,
                reason: "AC power required"
            )
        } else if lowBatteryLatched {
            applyProtection(
                active: true,
                reason: "Low battery protection"
            )
        } else {
            applyProtection(
                active: false,
                reason: nil
            )
        }
    }

    private func applyProtection(
        active: Bool,
        reason: String?
    ) {
        isProtectionActive = active
        protectionReason = reason

        sleepManager.setPausedForLowBattery(
            active,
            reason: reason
        )
    }

    // MARK: - Battery information

    private static func readBattery()
        -> BatteryInformation? {

        guard let snapshot =
            IOPSCopyPowerSourcesInfo()?
                .takeRetainedValue(),

            let sources =
                IOPSCopyPowerSourcesList(snapshot)?
                    .takeRetainedValue() as? [AnyObject]
        else {
            return nil
        }

        for source in sources {
            guard let info =
                IOPSGetPowerSourceDescription(
                    snapshot,
                    source
                )?.takeUnretainedValue()
                    as? [String: Any],

                info[kIOPSTypeKey] as? String ==
                    kIOPSInternalBatteryType,

                let current =
                    info[kIOPSCurrentCapacityKey] as? Int,

                let maximum =
                    info[kIOPSMaxCapacityKey] as? Int,

                maximum > 0
            else {
                continue
            }

            let percentage = min(
                100,
                max(0, current * 100 / maximum)
            )

            let onBattery =
                info[kIOPSPowerSourceStateKey]
                    as? String ==
                kIOPSBatteryPowerValue

            let charging =
                info[kIOPSIsChargingKey]
                    as? Bool ?? false

            let hardware = readHardwareInformation()

            return BatteryInformation(
                percentage: percentage,
                onBattery: onBattery,
                isCharging: charging,
                timeToEmpty: validMinutes(
                    info[kIOPSTimeToEmptyKey] as? Int
                ),
                timeToFull: validMinutes(
                    info[kIOPSTimeToFullChargeKey] as? Int
                ),
                cycleCount: hardware.cycleCount,
                healthPercentage: hardware.health
            )
        }

        return nil
    }

    private static func validMinutes(
        _ value: Int?
    ) -> Int? {
        guard let value, value >= 0 else {
            return nil
        }

        return value
    }

    private static func readHardwareInformation()
        -> (cycleCount: Int?, health: Double?) {

        guard let matching =
            IOServiceMatching("AppleSmartBattery")
        else {
            return (nil, nil)
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            matching
        )

        guard service != 0 else {
            return (nil, nil)
        }

        defer {
            IOObjectRelease(service)
        }

        func number(_ key: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? NSNumber
        }

        let cycles = number("CycleCount")?.intValue

        let designCapacity =
            number("DesignCapacity")?.doubleValue

        let maximumCapacity =
            number("AppleRawMaxCapacity")?.doubleValue

        var health: Double?

        if let designCapacity,
           let maximumCapacity,
           designCapacity > 0,
           maximumCapacity > 0 {

            health = min(
                100,
                maximumCapacity / designCapacity * 100
            )
        }

        return (cycles, health)
    }

    // MARK: - Battery history

    private func loadHistory() {
        guard let data = defaults.data(
            forKey: historyKey
        ),
        let samples = try? JSONDecoder().decode(
            [BatterySample].self,
            from: data
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(
            -historyRetention
        )

        history = samples.filter {
            $0.timestamp >= cutoff
        }

        lastHistorySample = history.last?.timestamp
    }

    private func recordHistory(
        _ battery: BatteryInformation
    ) {
        let now = Date()

        if let lastHistorySample,
           now.timeIntervalSince(lastHistorySample)
                < historyInterval {

            return
        }

        history.append(
            BatterySample(
                timestamp: now,
                percentage: battery.percentage,
                onBattery: battery.onBattery,
                isCharging: battery.isCharging
            )
        )

        let cutoff = now.addingTimeInterval(
            -historyRetention
        )

        history.removeAll {
            $0.timestamp < cutoff
        }

        lastHistorySample = now

        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(
                data,
                forKey: historyKey
            )
        }
    }

    func clearHistory() {
        history.removeAll()
        lastHistorySample = nil

        defaults.removeObject(forKey: historyKey)
    }

    // MARK: - Cleanup

    func shutdown() {
        timer?.invalidate()
        timer = nil

        if let source = notificationSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                source,
                .commonModes
            )

            CFRunLoopSourceInvalidate(source)

            notificationSource = nil
        }

        cancellables.removeAll()
    }
}