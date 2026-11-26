import Foundation
import Combine

@MainActor
final class AssertionMonitor: ObservableObject {
    @Published private(set) var assertions:
        [SleepAssertion] = []

    @Published private(set) var systemStatus:
        [String: Int] = [:]

    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                isEnabled,
                forKey: "assertions.enabled"
            )

            restart()
        }
    }

    @Published var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(
                refreshInterval,
                forKey: "assertions.interval"
            )

            restart()
        }
    }

    private var monitoringTask: Task<Void, Never>?
    private var generation = UUID()

    init() {
        let defaults = UserDefaults.standard

        isEnabled = defaults.object(
            forKey: "assertions.enabled"
        ) as? Bool ?? true

        refreshInterval = defaults.object(
            forKey: "assertions.interval"
        ) as? Double ?? 3

        restart()
    }

    // MARK: - Computed properties

    var processes: [AssertionProcess] {
        Dictionary(
            grouping: assertions,
            by: \.pid
        )
        .map { pid, items in
            AssertionProcess(
                pid: pid,
                name: items.first?.processName ?? "Unknown",
                assertions: items
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    var externalAssertions: [SleepAssertion] {
        assertions.filter {
            !$0.isOwnProcess
        }
    }

    var externalSleepBlockers: [SleepAssertion] {
        externalAssertions.filter {
            $0.preventsSystemSleep
        }
    }

    var externalDisplayBlockers: [SleepAssertion] {
        externalAssertions.filter {
            $0.preventsDisplaySleep
        }
    }

    var externalBlockingProcesses: [AssertionProcess] {
        processes.filter {
            !$0.isOwnProcess &&
            $0.preventsSystemSleep
        }
    }

    var hasExternalSleepBlockers: Bool {
        !externalSleepBlockers.isEmpty
    }

    var isSystemSleepBlocked: Bool {
        (systemStatus["PreventUserIdleSystemSleep"] ?? 0) > 0 ||
        (systemStatus["PreventSystemSleep"] ?? 0) > 0
    }

    var isDisplaySleepBlocked: Bool {
        (systemStatus["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }

    // MARK: - Monitoring

    func restart() {
        monitoringTask?.cancel()
        monitoringTask = nil

        generation = UUID()
        isRefreshing = false
        error = nil

        guard isEnabled else {
            assertions = []
            systemStatus = [:]
            lastUpdated = nil
            return
        }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()

                let configured =
                    self?.refreshInterval ?? 3

                let interval = configured.isFinite
                    ? min(max(configured, 1), 60)
                    : 3

                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(
                            interval * 1_000_000_000
                        )
                    )
                } catch {
                    break
                }
            }
        }
    }

    func refresh() async {
        guard isEnabled, !isRefreshing else {
            return
        }

        let currentGeneration = generation

        isRefreshing = true

        defer {
            if generation == currentGeneration {
                isRefreshing = false
            }
        }

        do {
            let snapshot = try await Task.detached(
                priority: .utility
            ) {
                let output = try Self.runPMSet()
                return Self.parse(output)
            }.value

            guard !Task.isCancelled,
                  isEnabled,
                  generation == currentGeneration else {
                return
            }

            assertions = snapshot.assertions
            systemStatus = snapshot.systemStatus
            lastUpdated = Date()
            error = nil

        } catch {
            guard !Task.isCancelled,
                  generation == currentGeneration else {
                return
            }

            assertions = []
            systemStatus = [:]

            self.error = error.localizedDescription
        }
    }

    // MARK: - Command execution

    nonisolated private static func runPMSet() throws -> String {
        let process = Process()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/pmset"
        )

        process.arguments = [
            "-g",
            "assertions"
        ]

        var environment =
            ProcessInfo.processInfo.environment

        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"

        process.environment = environment

        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let data = pipe.fileHandleForReading
            .readDataToEndOfFile()

        process.waitUntilExit()

        let output = String(
            decoding: data,
            as: UTF8.self
        )

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "KeepAwake.AssertionMonitor",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "pmset failed: \(output)"
                ]
            )
        }

        return output
    }

    // MARK: - Output parser

    nonisolated static func parse(
        _ output: String
    ) -> AssertionSnapshot {
        var snapshot = AssertionSnapshot()

        let statusPattern =
            #"^\s*([A-Za-z][A-Za-z0-9_]+)\s+(\d+)\s*$"#

        let assertionPattern =
            #"^\s*pid\s+(\d+)\((.*?)\):\s+\[([^\]]+)\]\s+(\S+)\s+(\S+)(?:\s+named:\s*"(.*?)")?"#

        guard let statusRegex = try? NSRegularExpression(
            pattern: statusPattern
        ),
        let assertionRegex = try? NSRegularExpression(
            pattern: assertionPattern
        ) else {
            return snapshot
        }

        var readingStatus = false
        var readingAssertions = false

        for line in output.components(
            separatedBy: .newlines
        ) {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if trimmed.hasPrefix(
                "Assertion status system-wide:"
            ) {
                readingStatus = true
                readingAssertions = false
                continue
            }

            if trimmed.hasPrefix(
                "Listed by owning process:"
            ) {
                readingStatus = false
                readingAssertions = true
                continue
            }

            if trimmed.hasPrefix("Kernel Assertions:") ||
               trimmed.hasPrefix("Idle sleep preventers:") {
                readingStatus = false
                readingAssertions = false
                continue
            }

            let text = line as NSString

            let range = NSRange(
                location: 0,
                length: text.length
            )

            if readingStatus,
               let match = statusRegex.firstMatch(
                    in: line,
                    range: range
               ) {
                let key = text.substring(
                    with: match.range(at: 1)
                )

                let value = text.substring(
                    with: match.range(at: 2)
                )

                snapshot.systemStatus[key] =
                    Int(value) ?? 0
            }

            if readingAssertions,
               let match = assertionRegex.firstMatch(
                    in: line,
                    range: range
               ) {
                func group(_ index: Int) -> String {
                    let range = match.range(at: index)

                    guard range.location != NSNotFound else {
                        return ""
                    }

                    return text.substring(with: range)
                }

                guard let pid = Int32(group(1)) else {
                    continue
                }

                snapshot.assertions.append(
                    SleepAssertion(
                        pid: pid,
                        processName: group(2),
                        assertionID: group(3),
                        duration: group(4),
                        type: group(5),
                        name: group(6)
                    )
                )
            }
        }

        return snapshot
    }
}