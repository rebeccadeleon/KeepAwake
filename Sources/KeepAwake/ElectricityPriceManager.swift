import Foundation
import Combine

struct ElectricityPrice: Codable {
    let price: Double
    let currency: String
    let unit: String
    let validUntil: Date
}

@MainActor
final class ElectricityPriceManager: ObservableObject {
    @Published var isEnabled: Bool = false {
        didSet {
            save()
            restart()
        }
    }

    @Published var endpoint: String = "" {
        didSet {
            save()
            restart()
        }
    }

    @Published var maximumPrice: Double = 20 {
        didSet {
            save()
            evaluate()
        }
    }

    @Published private(set) var currentPrice:
        ElectricityPrice?

    @Published private(set) var lastChecked: Date?
    @Published private(set) var error: String?

    @Published private(set) var isChecking = false
    @Published private(set) var isLowPrice = false

    private let sleepManager: SleepManager

    private var pollingTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    private let interval: UInt64 = 300

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager

        let defaults = UserDefaults.standard

        isEnabled = defaults.bool(
            forKey: "electricity.enabled"
        )

        endpoint = defaults.string(
            forKey: "electricity.endpoint"
        ) ?? ""

        maximumPrice = defaults.object(
            forKey: "electricity.maximumPrice"
        ) as? Double ?? 20

        restart()
    }

    func restart() {
        pollingTask?.cancel()
        expiryTask?.cancel()

        currentPrice = nil
        error = nil
        isChecking = false

        evaluate()

        guard isEnabled else {
            return
        }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()

                do {
                    try await Task.sleep(
                        nanoseconds: 300_000_000_000
                    )
                } catch {
                    break
                }
            }
        }
    }

    func refresh() async {
        guard isEnabled, !isChecking else {
            return
        }

        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            error = "Enter a valid HTTPS endpoint."
            currentPrice = nil
            evaluate()
            return
        }

        isChecking = true

        defer {
            isChecking = false
        }

        do {
            var request = URLRequest(url: url)

            request.timeoutInterval = 15
            request.cachePolicy =
                .reloadIgnoringLocalCacheData

            let (data, response) =
                try await URLSession.shared.data(
                    for: request
                )

            guard !Task.isCancelled,
                  isEnabled,
                  URL(string: endpoint) == url else {
                return
            }

            guard let http = response
                as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                http.url?.scheme == "https" else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let result = try decoder.decode(
                ElectricityPrice.self,
                from: data
            )

            guard result.price.isFinite,
                  result.unit.lowercased() == "kwh",
                  result.validUntil > Date() else {
                throw URLError(.cannotParseResponse)
            }

            currentPrice = result
            lastChecked = Date()
            error = nil

            evaluate()
            scheduleExpiry(result.validUntil)

        } catch {
            guard !Task.isCancelled else {
                return
            }

            currentPrice = nil
            self.error = error.localizedDescription

            evaluate()
        }
    }

    private func scheduleExpiry(_ date: Date) {
        expiryTask?.cancel()

        let seconds = max(
            0,
            date.timeIntervalSinceNow
        )

        // Limit a single timer to a reasonable period.
        let delay = min(seconds, 86_400)

        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        delay * 1_000_000_000
                    )
                )
            } catch {
                return
            }

            self?.evaluate()
        }
    }

    private func evaluate() {
        guard isEnabled,
              let price = currentPrice,
              price.validUntil > Date(),
              price.price <= maximumPrice else {
            isLowPrice = false

            sleepManager.setAutomaticReason(
                .electricity,
                text: nil
            )

            return
        }

        isLowPrice = true

        let formatted = String(
            format: "%.2f",
            price.price
        )

        sleepManager.setAutomaticReason(
            .electricity,
            text: "Low energy price: \(formatted) \(price.currency)/kWh"
        )
    }

    private func save() {
        let defaults = UserDefaults.standard

        defaults.set(
            isEnabled,
            forKey: "electricity.enabled"
        )

        defaults.set(
            endpoint,
            forKey: "electricity.endpoint"
        )

        defaults.set(
            maximumPrice,
            forKey: "electricity.maximumPrice"
        )
    }
}