import Foundation

struct ResourceSample: Identifiable {
    let id = UUID()
    let timestamp: Date

    let cpuUsage: Double?

    let memoryUsed: UInt64?
    let memoryTotal: UInt64

    let downloadSpeed: Double?
    let uploadSpeed: Double?

    let diskReadSpeed: Double?
    let diskWriteSpeed: Double?

    var memoryUsage: Double? {
        guard let memoryUsed, memoryTotal > 0 else {
            return nil
        }

        return Double(memoryUsed) /
            Double(memoryTotal) * 100
    }

    var networkSpeed: Double? {
        guard let downloadSpeed, let uploadSpeed else {
            return nil
        }

        return downloadSpeed + uploadSpeed
    }

    var diskSpeed: Double? {
        guard let diskReadSpeed, let diskWriteSpeed else {
            return nil
        }

        return diskReadSpeed + diskWriteSpeed
    }
}

struct ResourcePreferences: Codable, Equatable {
    var isEnabled = false

    var samplingInterval: Double = 3

    var cpuProtection = false
    var cpuThreshold: Double = 30

    var networkProtection = false
    var networkThreshold: Double = 5

    var diskProtection = false
    var diskThreshold: Double = 10

    var activationDelay: Double = 9
    var releaseDelay: Double = 60
}

struct ResourceCounters {
    let read: UInt64
    let written: UInt64
}

struct ResourceTrigger {
    private(set) var isActive = false

    private var aboveSince: TimeInterval?
    private var belowSince: TimeInterval?

    mutating func evaluate(
        enabled: Bool,
        value: Double?,
        threshold: Double,
        activationDelay: TimeInterval,
        releaseDelay: TimeInterval,
        now: TimeInterval
    ) -> Bool {
        guard enabled,
              let value,
              value.isFinite else {
            reset()
            return false
        }

        if isActive {
            // Hysteresis prevents frequent switching
            // near the configured threshold.
            if value < threshold * 0.8 {
                if belowSince == nil {
                    belowSince = now
                }

                if now - (belowSince ?? now) >= releaseDelay {
                    reset()
                }
            } else {
                belowSince = nil
            }
        } else {
            if value >= threshold {
                if aboveSince == nil {
                    aboveSince = now
                }

                if now - (aboveSince ?? now) >= activationDelay {
                    isActive = true
                    belowSince = nil
                }
            } else {
                aboveSince = nil
            }
        }

        return isActive
    }

    mutating func reset() {
        isActive = false
        aboveSince = nil
        belowSince = nil
    }
}

enum ResourceFormatter {
    static func percentage(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }

        return String(format: "%.1f%%", value)
    }

    static func speed(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }

        if value >= 1_000_000 {
            return String(
                format: "%.2f MB/s",
                value / 1_000_000
            )
        }

        if value >= 1_000 {
            return String(
                format: "%.1f KB/s",
                value / 1_000
            )
        }

        return String(format: "%.0f B/s", value)
    }

    static func bytes(_ value: UInt64?) -> String {
        guard let value else {
            return "—"
        }

        return ByteCountFormatter.string(
            fromByteCount: Int64(clamping: value),
            countStyle: .memory
        )
    }
}