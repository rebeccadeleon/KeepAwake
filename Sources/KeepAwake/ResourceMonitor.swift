import Foundation
import Combine
import AppKit

private actor ResourceSampler {
    private let cpu = CPUUsageCollector()
    private let network = NetworkUsageCollector()
    private let disk = DiskUsageCollector()

    func sample() -> ResourceSample {
        let cpuUsage = cpu.sample()
        let memory = MemoryUsageCollector.sample()
        let networkUsage = network.sample()
        let diskUsage = disk.sample()

        return ResourceSample(
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsed: memory,
            memoryTotal:
                ProcessInfo.processInfo.physicalMemory,
            downloadSpeed: networkUsage?.download,
            uploadSpeed: networkUsage?.upload,
            diskReadSpeed: diskUsage?.read,
            diskWriteSpeed: diskUsage?.write
        )
    }
}

@MainActor
final class ResourceMonitor: ObservableObject {
    private static let preferencesKey =
        "resources.preferences"

    @Published var preferences = ResourcePreferences() {
        didSet {
            guard oldValue != preferences else {
                return
            }

            savePreferences()

            if oldValue.isEnabled != preferences.isEnabled ||
                oldValue.samplingInterval !=
                    preferences.samplingInterval {

                restart()
            } else {
                resetTriggers()
            }
        }
    }

    @Published private(set) var latest: ResourceSample?

    @Published private(set) var history:
        [ResourceSample] = []

    @Published private(set) var cpuProtectionActive = false

    @Published private(set) var networkProtectionActive = false

    @Published private(set) var diskProtectionActive = false

    @Published private(set) var isMonitoring = false

    private let sleepManager: SleepManager

    private var sampler = ResourceSampler()

    private var monitoringTask: Task<Void, Never>?

    private var generation = UUID()

    private var cpuTrigger = ResourceTrigger()
    private var networkTrigger = ResourceTrigger()
    private var diskTrigger = ResourceTrigger()

    private var cancellables = Set<AnyCancellable>()

    private var isSystemSleeping = false

    private let historyDuration: TimeInterval = 300

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager

        if let data = UserDefaults.standard.data(
            forKey: Self.preferencesKey
        ),
        let saved = try? JSONDecoder().decode(
            ResourcePreferences.self,
            from: data
        ) {
            preferences = saved
        }

        observeSystemEvents()
        restart()
    }

    var hasActiveProtection: Bool {
        cpuProtectionActive ||
        networkProtectionActive ||
        diskProtectionActive
    }

    // MARK: - Preferences

    private func savePreferences() {
        guard let data = try? JSONEncoder().encode(
            preferences
        ) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.preferencesKey
        )
    }

    func restoreDefaults() {
        preferences = ResourcePreferences()
    }

    // MARK: - Monitoring

    func restart() {
        stopMonitoring()

        guard preferences.isEnabled,
              !isSystemSleeping else {
            return
        }

        sampler = ResourceSampler()

        let currentSampler = sampler
        let currentGeneration = generation

        isMonitoring = true

        monitoringTask = Task {
            @MainActor [weak self] in

            while !Task.isCancelled {
                let sample = await currentSampler.sample()

                guard !Task.isCancelled,
                      let self,
                      self.generation == currentGeneration else {
                    return
                }

                self.processSample(sample)

                let interval = self.preferences.samplingInterval

                let seconds = interval.isFinite
                    ? min(60, max(1, interval))
                    : 3

                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(
                            seconds * 1_000_000_000
                        )
                    )
                } catch {
                    return
                }
            }
        }
    }

    func stopMonitoring() {
        generation = UUID()

        monitoringTask?.cancel()
        monitoringTask = nil

        isMonitoring = false
        latest = nil
        history.removeAll()

        resetTriggers()
    }

    private func processSample(
        _ sample: ResourceSample
    ) {
        latest = sample

        history.append(sample)

        let cutoff = sample.timestamp.addingTimeInterval(
            -historyDuration
        )

        history.removeAll {
            $0.timestamp < cutoff
        }

        evaluateTriggers(sample)
    }

    // MARK: - Automatic protection

    private func evaluateTriggers(
        _ sample: ResourceSample
    ) {
        let now = ProcessInfo.processInfo.systemUptime

        cpuProtectionActive = cpuTrigger.evaluate(
            enabled: preferences.cpuProtection,
            value: sample.cpuUsage,
            threshold: preferences.cpuThreshold,
            activationDelay: preferences.activationDelay,
            releaseDelay: preferences.releaseDelay,
            now: now
        )

        networkProtectionActive = networkTrigger.evaluate(
            enabled: preferences.networkProtection,
            value: sample.networkSpeed.map {
                $0 / 1_000_000
            },
            threshold: preferences.networkThreshold,
            activationDelay: preferences.activationDelay,
            releaseDelay: preferences.releaseDelay,
            now: now
        )

        diskProtectionActive = diskTrigger.evaluate(
            enabled: preferences.diskProtection,
            value: sample.diskSpeed.map {
                $0 / 1_000_000
            },
            threshold: preferences.diskThreshold,
            activationDelay: preferences.activationDelay,
            releaseDelay: preferences.releaseDelay,
            now: now
        )

        updateAwakeReasons()
    }

    private func updateAwakeReasons() {
        sleepManager.setAutomaticReason(
            .cpuActivity,
            text: cpuProtectionActive
                ? "CPU activity protection"
                : nil
        )

        sleepManager.setAutomaticReason(
            .networkActivity,
            text: networkProtectionActive
                ? "Network transfer protection"
                : nil
        )

        sleepManager.setAutomaticReason(
            .diskActivity,
            text: diskProtectionActive
                ? "Disk activity protection"
                : nil
        )
    }

    private func resetTriggers() {
        cpuTrigger.reset()
        networkTrigger.reset()
        diskTrigger.reset()

        cpuProtectionActive = false
        networkProtectionActive = false
        diskProtectionActive = false

        updateAwakeReasons()
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
                guard let self else {
                    return
                }

                self.isSystemSleeping = true
                self.stopMonitoring()
            }
        }
        .store(in: &cancellables)

        center.publisher(
            for: NSWorkspace.didWakeNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.isSystemSleeping = false
                self.restart()
            }
        }
        .store(in: &cancellables)
    }
}