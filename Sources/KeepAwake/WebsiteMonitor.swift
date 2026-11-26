import Foundation
import Combine

struct WebsiteTarget: Codable, Identifiable {
    var id = UUID()

    var name: String
    var url: String
    var isEnabled = true
}

enum WebsiteStatus: String {
    case unknown = "Waiting"
    case online = "Online"
    case slow = "Slow"
    case offline = "Offline"
}

struct WebsiteResult {
    let status: WebsiteStatus
    let statusCode: Int?
    let latency: Double?
    let checkedAt: Date
    let error: String?
}

@MainActor
final class WebsiteMonitor: ObservableObject {
    @Published private(set) var targets:
        [WebsiteTarget] = []

    @Published private(set) var results:
        [UUID: WebsiteResult] = [:]

    @Published var isEnabled = false {
        didSet {
            save()
            restart()
        }
    }

    @Published var keepAwake = false {
        didSet {
            save()
            updateAwakeReason()
        }
    }

    @Published var checkInterval: Double = 60 {
        didSet {
            save()
            restart()
        }
    }

    @Published var slowThreshold: Double = 1000 {
        didSet {
            save()
        }
    }

    @Published private(set) var isChecking = false

    private let sleepManager: SleepManager

    private var pollingTask: Task<Void, Never>?

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager

        let defaults = UserDefaults.standard

        if let data = defaults.data(
            forKey: "website.targets"
        ) {
            targets = (
                try? JSONDecoder().decode(
                    [WebsiteTarget].self,
                    from: data
                )
            ) ?? []
        }

        isEnabled = defaults.bool(
            forKey: "website.enabled"
        )

        keepAwake = defaults.bool(
            forKey: "website.keepAwake"
        )

        checkInterval = defaults.object(
            forKey: "website.interval"
        ) as? Double ?? 60

        slowThreshold = defaults.object(
            forKey: "website.threshold"
        ) as? Double ?? 1000

        restart()
    }

    func add(name: String, url: String) {
        guard let parsed = URL(string: url),
              parsed.scheme?.lowercased() == "https",
              let host = parsed.host else {
            return
        }

        targets.append(
            WebsiteTarget(
                name: name.isEmpty ? host : name,
                url: url
            )
        )

        save()
        restart()
    }

    func remove(_ id: UUID) {
        targets.removeAll {
            $0.id == id
        }

        results.removeValue(forKey: id)

        save()
        restart()
    }

    func setEnabled(
        _ id: UUID,
        enabled: Bool
    ) {
        guard let index = targets.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }

        targets[index].isEnabled = enabled

        save()
        restart()
    }

    func restart() {
        pollingTask?.cancel()
        pollingTask = nil

        isChecking = false

        updateAwakeReason()

        guard isEnabled else {
            return
        }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAll()

                let interval = max(
                    self?.checkInterval ?? 60,
                    15
                )

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

    func checkAll() async {
        guard isEnabled, !isChecking else {
            return
        }

        isChecking = true

        defer {
            isChecking = false
        }

        let activeTargets = targets.filter {
            $0.isEnabled
        }

        let threshold = slowThreshold

        await withTaskGroup(
            of: (UUID, WebsiteResult).self
        ) { group in

            for target in activeTargets {
                group.addTask {
                    let result = await Self.check(
                        target,
                        threshold: threshold
                    )

                    return (target.id, result)
                }
            }

            for await (id, result) in group {
                guard !Task.isCancelled,
                      isEnabled,
                      targets.contains(
                        where: {
                            $0.id == id &&
                            $0.isEnabled
                        }
                      ) else {
                    continue
                }

                results[id] = result
            }
        }
    }

    nonisolated private static func check(
        _ target: WebsiteTarget,
        threshold: Double
    ) async -> WebsiteResult {
        let start = ProcessInfo.processInfo.systemUptime

        do {
            guard let url = URL(string: target.url),
                  url.scheme == "https" else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)

            request.httpMethod = "HEAD"
            request.timeoutInterval = 10
            request.cachePolicy =
                .reloadIgnoringLocalCacheData

            let (_, response) =
                try await URLSession.shared.data(
                    for: request
                )

            guard let http = response
                as? HTTPURLResponse,
                http.url?.scheme == "https" else {
                throw URLError(.badServerResponse)
            }

            let latency = (
                ProcessInfo.processInfo.systemUptime
                - start
            ) * 1000

            let status: WebsiteStatus

            if !(200...399).contains(http.statusCode) {
                status = .offline
            } else if latency > threshold {
                status = .slow
            } else {
                status = .online
            }

            return WebsiteResult(
                status: status,
                statusCode: http.statusCode,
                latency: latency,
                checkedAt: Date(),
                error: nil
            )

        } catch {
            return WebsiteResult(
                status: .offline,
                statusCode: nil,
                latency: nil,
                checkedAt: Date(),
                error: error.localizedDescription
            )
        }
    }

    private func updateAwakeReason() {
        let count = targets.filter {
            $0.isEnabled
        }.count

        sleepManager.setAutomaticReason(
            .websiteMonitoring,
            text: isEnabled && keepAwake && count > 0
                ? "Monitoring \(count) website(s)"
                : nil
        )
    }

    private func save() {
        let defaults = UserDefaults.standard

        if let data = try? JSONEncoder().encode(
            targets
        ) {
            defaults.set(
                data,
                forKey: "website.targets"
            )
        }

        defaults.set(
            isEnabled,
            forKey: "website.enabled"
        )

        defaults.set(
            keepAwake,
            forKey: "website.keepAwake"
        )

        defaults.set(
            checkInterval,
            forKey: "website.interval"
        )

        defaults.set(
            slowThreshold,
            forKey: "website.threshold"
        )
    }
}