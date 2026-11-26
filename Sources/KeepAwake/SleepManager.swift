import Foundation
import Combine
import IOKit.pwr_mgt

enum AwakeState: Equatable {
    case inactive
    case active
    case pausedLowBattery
    case pausedManually
    case failed(String)
}

enum AutomaticAwakeReason: String, CaseIterable, Hashable {
    case downloads
    case electricity
    case websiteMonitoring
}

@MainActor
final class SleepManager: ObservableObject {
    private static let allowDisplaySleepKey = "allowDisplaySleep"

    @Published private(set) var isManualActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var remainingText: String?
    @Published private(set) var isPausedForLowBattery = false
    @Published private(set) var isPausedManually = false
    @Published private(set) var scheduleEndText: String?
    @Published private(set) var triggeringApps: [String] = []
    @Published private(set) var state: AwakeState = .inactive
    @Published private(set) var assertionError: String?
    @Published private(set) var automaticReasons:
    [AutomaticAwakeReason: String] = [:]

    @Published var allowDisplaySleep =
        UserDefaults.standard.bool(
            forKey: SleepManager.allowDisplaySleepKey
        ) {
        didSet {
            guard oldValue != allowDisplaySleep else {
                return
            }

            UserDefaults.standard.set(
                allowDisplaySleep,
                forKey: Self.allowDisplaySleepKey
            )

            updateAssertion()
        }
    }

    private var assertionID: IOPMAssertionID?
    private var assertionAllowsDisplaySleep: Bool?
    private var timer: Timer?

    // MARK: - State

    var wantsAwake: Bool {
        isManualActive ||
        !triggeringApps.isEmpty ||
        scheduleEndText != nil ||
        !automaticReasons.isEmpty
    }

    func setAutomaticReason(
        _ reason: AutomaticAwakeReason,
        text: String?
    ) {
        guard automaticReasons[reason] != text else {
            return
        }

        if let text {
            automaticReasons[reason] = text
        } else {
            automaticReasons.removeValue(
                forKey: reason
            )
        }

        updateAssertion()
    }

    var isActive: Bool {
        assertionID != nil
    }

    var shouldHoldAssertion: Bool {
        wantsAwake &&
        !isPausedForLowBattery &&
        !isPausedManually
    }

    var statusText: String {
        switch state {
        case .inactive:
            return "KeepAwake is off"

        case .active:
            return "Your Mac is awake"

        case .pausedLowBattery:
            return "Paused: Low battery"

        case .pausedManually:
            return "Paused manually"

        case .failed:
            return "Power assertion error"
        }
    }

    var reasonText: String {
        var reasons: [String] = []

        if isManualActive {
            if let endDate {
                let formattedTime = endDate.formatted(
                    date: .omitted,
                    time: .shortened
                )

                reasons.append("Until \(formattedTime)")
            } else {
                reasons.append("Indefinite session")
            }
        }

        if !triggeringApps.isEmpty {
            reasons.append(
                triggeringApps.joined(separator: ", ")
            )
        }

        if let scheduleEndText {
            reasons.append(
                "Scheduled until \(scheduleEndText)"
            )
        }

        for reason in AutomaticAwakeReason.allCases {
            if let text = automaticReasons[reason] {
                reasons.append(text)
            }
        }

        return reasons.isEmpty
            ? "No active session"
            : reasons.joined(separator: " · ")
    }

    // MARK: - Manual session

    func activate(for duration: TimeInterval? = nil) {
        if let duration {
            guard duration.isFinite, duration > 0 else {
                return
            }
        }

        stopTimer()

        isManualActive = true
        isPausedManually = false

        if let duration {
            endDate = Date().addingTimeInterval(duration)
            startTimer()
        }

        updateAssertion()
    }

    func deactivate() {
        stopTimer()
        isManualActive = false
        updateAssertion()
    }

    func extend(by duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else {
            return
        }

        guard isManualActive else {
            activate(for: duration)
            return
        }

        guard let endDate else {
            return
        }

        self.endDate = max(endDate, Date())
            .addingTimeInterval(duration)

        updateRemainingText()
    }

    // MARK: - Global pause

    func pause() {
        isPausedManually = true
        updateAssertion()
    }

    func resume() {
        isPausedManually = false
        updateAssertion()
    }

    func togglePause() {
        if isPausedManually {
            resume()
        } else {
            pause()
        }
    }

    func stopAll() {
        stopTimer()
        isManualActive = false
        isPausedManually = true
        updateAssertion()
    }

    func toggle() {
        if isPausedManually {
            if wantsAwake {
                resume()
            } else {
                activate()
            }
        } else if wantsAwake {
            pause()
        } else {
            activate()
        }
    }

    func retry() {
        updateAssertion()
    }

    // MARK: - Automatic triggers

    func setPausedForLowBattery(_ paused: Bool) {
        if isPausedForLowBattery != paused {
            isPausedForLowBattery = paused
        }

        updateAssertion()
    }

    func setSchedule(endText: String?) {
        if scheduleEndText != endText {
            scheduleEndText = endText
        }

        updateAssertion()
    }

    func setTriggeringApps(_ names: [String]) {
        if triggeringApps != names {
            triggeringApps = names
        }

        updateAssertion()
    }

    // MARK: - Power assertions

    private func updateAssertion() {
        assertionError = nil

        guard shouldHoldAssertion else {
            guard releaseAssertion() else {
                return
            }

            if !wantsAwake {
                state = .inactive
            } else if isPausedManually {
                state = .pausedManually
            } else if isPausedForLowBattery {
                state = .pausedLowBattery
            } else {
                state = .inactive
            }

            return
        }

        if assertionID != nil,
           assertionAllowsDisplaySleep == allowDisplaySleep {
            state = .active
            return
        }

        let type = allowDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleSystemSleep
            : kIOPMAssertionTypePreventUserIdleDisplaySleep

        var newID = IOPMAssertionID(0)

        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "KeepAwake active session" as CFString,
            &newID
        )

        guard result == kIOReturnSuccess else {
            reportError(
                "Unable to create power assertion (\(result))."
            )
            return
        }

        // Acquire the replacement before releasing the old one.
        if let oldID = assertionID {
            let releaseResult = IOPMAssertionRelease(oldID)

            guard releaseResult == kIOReturnSuccess else {
                IOPMAssertionRelease(newID)

                reportError(
                    "Unable to replace power assertion (\(releaseResult))."
                )
                return
            }
        }

        assertionID = newID
        assertionAllowsDisplaySleep = allowDisplaySleep

        state = .active
    }

    @discardableResult
    private func releaseAssertion() -> Bool {
        guard let assertionID else {
            return true
        }

        let result = IOPMAssertionRelease(assertionID)

        guard result == kIOReturnSuccess else {
            reportError(
                "Unable to release power assertion (\(result))."
            )
            return false
        }

        self.assertionID = nil
        assertionAllowsDisplaySleep = nil

        return true
    }

    private func reportError(_ message: String) {
        assertionError = message
        state = .failed(message)

        NSLog("KeepAwake: \(message)")
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()

        updateRemainingText()

        let newTimer = Timer(
            timeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil

        endDate = nil
        remainingText = nil
    }

    private func tick() {
        guard let endDate else {
            return
        }

        if Date() >= endDate {
            deactivate()
        } else {
            updateRemainingText()
        }
    }

    private func updateRemainingText() {
        guard let endDate else {
            return
        }

        let text = Self.format(
            endDate.timeIntervalSinceNow
        )

        if remainingText != text {
            remainingText = text
        }
    }

    private static func format(
        _ seconds: TimeInterval
    ) -> String {
        let totalMinutes = max(
            1,
            Int((seconds / 60).rounded(.up))
        )

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        return minutes == 0
            ? "\(hours)h"
            : "\(hours)h \(minutes)m"
    }
}