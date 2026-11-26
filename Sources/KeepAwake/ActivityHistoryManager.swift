import Foundation
import AppKit
import Combine

@MainActor
final class ActivityHistoryManager: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []

    @Published private(set) var analytics =
        ActivityAnalytics()

    @Published private(set) var error: String?

    @Published var period: ActivityPeriod = .week {
        didSet {
            refresh()
        }
    }

    @Published var retentionDays: Int =
        UserDefaults.standard.object(
            forKey: "activity.retentionDays"
        ) as? Int ?? 90 {
        didSet {
            UserDefaults.standard.set(
                retentionDays,
                forKey: "activity.retentionDays"
            )

            performMaintenance()
            refresh()
        }
    }

    private let sleepManager: SleepManager
    private let assertionMonitor: AssertionMonitor
    private let downloadManager: DownloadManager

    private var store: ActivityHistoryStore?

    private var cancellables =
        Set<AnyCancellable>()

    private var timer: Timer?

    private var activeIntervalID: String?

    private var previousActive = false
    private var previousPaused = false

    private var previousAssertions:
        [String: String] = [:]

    private var previousDownloads:
        [UUID: String] = [:]

    private var isSystemSleeping = false
    private var isStopped = false

    private var lastMaintenance = Date.distantPast

    init(
        sleepManager: SleepManager,
        assertionMonitor: AssertionMonitor,
        downloadManager: DownloadManager
    ) {
        self.sleepManager = sleepManager
        self.assertionMonitor = assertionMonitor
        self.downloadManager = downloadManager

        do {
            store = try ActivityHistoryStore()
        } catch {
            self.error = error.localizedDescription
        }

        previousAssertions = assertionSnapshot(
            assertionMonitor.assertions
        )

        previousDownloads = Dictionary(
            uniqueKeysWithValues:
                downloadManager.items.map {
                    ($0.id, $0.state.rawValue)
                }
        )

        record(
            .applicationStarted,
            detail: "KeepAwake \(AppInfo.version)"
        )

        observeSleepManager()
        observeAssertions()
        observeDownloads()
        observeSystemEvents()

        synchronizeSleepState()
        performMaintenance()
        startTimer()
        refresh()
    }

    // MARK: - Event recording

    func record(
        _ type: ActivityType,
        detail: String = ""
    ) {
        guard !isStopped, let store else {
            return
        }

        do {
            try store.insert(
                ActivityEvent(
                    type: type,
                    detail: detail
                )
            )

            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Sleep prevention

    private func observeSleepManager() {
        sleepManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.synchronizeSleepState()
                }
            }
            .store(in: &cancellables)
    }

    private func synchronizeSleepState() {
        guard !isStopped else {
            return
        }

        let active =
            sleepManager.isActive &&
            !isSystemSleeping

        let paused =
            sleepManager.wantsAwake &&
            (
                sleepManager.isPausedManually ||
                sleepManager.isPausedForLowBattery
            )

        let wasActive = previousActive
        let wasPaused = previousPaused

        previousActive = active
        previousPaused = paused

        if active && !wasActive {
            beginAwakeInterval()

            record(
                wasPaused
                    ? .sessionResumed
                    : .sessionStarted,
                detail: sleepManager.reasonText
            )

        } else if !active && wasActive {
            endAwakeInterval()

            if paused {
                record(
                    .sessionPaused,
                    detail: sleepManager.isPausedForLowBattery
                        ? "Low battery protection"
                        : "Manually paused"
                )
            } else {
                record(
                    .sessionStopped,
                    detail: isSystemSleeping
                        ? "System sleep"
                        : sleepManager.statusText
                )
            }
        }
    }

    private func beginAwakeInterval() {
        guard activeIntervalID == nil,
              let store else {
            return
        }

        let id = UUID().uuidString

        do {
            try store.beginInterval(
                id: id,
                at: Date()
            )

            activeIntervalID = id
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func endAwakeInterval() {
        guard let id = activeIntervalID,
              let store else {
            return
        }

        do {
            try store.endInterval(
                id: id,
                at: Date()
            )

            activeIntervalID = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - External assertions

    private func assertionSnapshot(
        _ assertions: [SleepAssertion]
    ) -> [String: String] {
        var result: [String: String] = [:]

        for assertion in assertions {
            guard !assertion.isOwnProcess,
                  assertion.preventsSystemSleep else {
                continue
            }

            result[assertion.id] =
                "\(assertion.processName) · PID \(assertion.pid)"
        }

        return result
    }

    private func observeAssertions() {
        assertionMonitor.$assertions
            .dropFirst()
            .sink { [weak self] assertions in
                Task { @MainActor [weak self] in
                    self?.processAssertions(assertions)
                }
            }
            .store(in: &cancellables)
    }

    private func processAssertions(
        _ assertions: [SleepAssertion]
    ) {
        guard !isStopped else {
            return
        }

        guard assertionMonitor.isEnabled,
              assertionMonitor.error == nil else {
            return
        }

        let current = assertionSnapshot(assertions)

        for (id, name) in current {
            if previousAssertions[id] == nil {
                record(
                    .externalAssertionStarted,
                    detail: name
                )
            }
        }

        for (id, name) in previousAssertions {
            if current[id] == nil {
                record(
                    .externalAssertionStopped,
                    detail: name
                )
            }
        }

        previousAssertions = current
    }

    // MARK: - Downloads

    private func observeDownloads() {
        downloadManager.$items
            .dropFirst()
            .sink { [weak self] items in
                Task { @MainActor [weak self] in
                    self?.processDownloads(items)
                }
            }
            .store(in: &cancellables)
    }

    private func processDownloads(
        _ items: [DownloadItem]
    ) {
        guard !isStopped else {
            return
        }

        for item in items {
            let state = item.state.rawValue

            guard previousDownloads[item.id] != state else {
                continue
            }

            previousDownloads[item.id] = state

            switch item.state {
            case .downloading:
                record(
                    .downloadStarted,
                    detail: item.fileName
                )

            case .completed:
                record(
                    .downloadCompleted,
                    detail: item.fileName
                )

            case .failed:
                record(
                    .downloadFailed,
                    detail: item.fileName
                )

            case .cancelled:
                record(
                    .downloadCancelled,
                    detail: item.fileName
                )
            }
        }

        let currentIDs = Set(items.map(\.id))

        previousDownloads = previousDownloads.filter {
            currentIDs.contains($0.key)
        }
    }

    // MARK: - System sleep and wake

    private func observeSystemEvents() {
        let center =
            NSWorkspace.shared.notificationCenter

        center.publisher(
            for: NSWorkspace.willSleepNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemSleep()
            }
        }
        .store(in: &cancellables)

        center.publisher(
            for: NSWorkspace.didWakeNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
        .store(in: &cancellables)
    }

    private func handleSystemSleep() {
        isSystemSleeping = true

        synchronizeSleepState()

        record(
            .systemSleep,
            detail: "macOS sleep notification"
        )
    }

    private func handleSystemWake() {
        isSystemSleeping = false

        record(
            .systemWake,
            detail: "macOS wake notification"
        )

        synchronizeSleepState()
    }

    // MARK: - Timer

    private func startTimer() {
        let timer = Timer(
            timeInterval: 15,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }

        RunLoop.main.add(
            timer,
            forMode: .common
        )

        self.timer = timer
    }

    private func tick() {
        guard !isStopped else {
            return
        }

        synchronizeSleepState()

        if let id = activeIntervalID,
           !isSystemSleeping {
            do {
                try store?.heartbeat(
                    id: id,
                    at: Date()
                )
            } catch {
                self.error = error.localizedDescription
            }
        }

        if Date().timeIntervalSince(
            lastMaintenance
        ) >= 3600 {
            performMaintenance()
        }

        refresh()
    }

    // MARK: - Analytics

    func refresh() {
        guard let store else {
            return
        }

        do {
            let start = period.startDate
            let now = Date()

            events = try store.fetchEvents(
                since: start
            )

            let intervals = try store.fetchIntervals(
                since: start,
                until: now
            )

            var result = ActivityAnalytics()

            result.awakeDuration = intervals.reduce(0) {
                total, interval in

                let lower = max(
                    interval.startedAt,
                    start
                )

                let upper = min(
                    interval.endedAt,
                    now
                )

                return total + max(
                    0,
                    upper.timeIntervalSince(lower)
                )
            }

            result.sessionCount = intervals.count

            result.sleepCount = try store.countEvents(
                .systemSleep,
                since: start
            )

            result.wakeCount = try store.countEvents(
                .systemWake,
                since: start
            )

            result.completedDownloads =
                try store.countEvents(
                    .downloadCompleted,
                    since: start
                )

            result.failedDownloads =
                try store.countEvents(
                    .downloadFailed,
                    since: start
                )

            result.dailyActivity = calculateDailyActivity(
                intervals: intervals,
                start: start,
                now: now
            )

            analytics = result
            error = nil

        } catch {
            self.error = error.localizedDescription
        }
    }

    private func calculateDailyActivity(
        intervals: [ActivityInterval],
        start: Date,
        now: Date
    ) -> [DailyActivity] {
        let calendar = Calendar.current

        var result: [DailyActivity] = []
        var day = start

        while day <= now {
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                break
            }

            let duration = intervals.reduce(0.0) {
                total, interval in

                let lower = max(
                    interval.startedAt,
                    day
                )

                let upper = min(
                    interval.endedAt,
                    nextDay,
                    now
                )

                return total + max(
                    0,
                    upper.timeIntervalSince(lower)
                )
            }

            result.append(
                DailyActivity(
                    date: day,
                    duration: duration
                )
            )

            day = nextDay
        }

        return result
    }

    // MARK: - Maintenance

    func performMaintenance() {
        guard retentionDays > 0,
              let store else {
            return
        }

        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date()
        ) else {
            return
        }

        do {
            try store.deleteOlderThan(cutoff)
            lastMaintenance = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearHistory() {
        guard let store else {
            return
        }

        do {
            try store.clear()

            activeIntervalID = nil

            if sleepManager.isActive &&
               !isSystemSleeping {
                beginAwakeInterval()
            }

            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func shutdown() {
        guard !isStopped else {
            return
        }

        endAwakeInterval()

        record(
            .applicationStopped,
            detail: "KeepAwake terminated"
        )

        isStopped = true

        timer?.invalidate()
        timer = nil

        cancellables.removeAll()
    }
}