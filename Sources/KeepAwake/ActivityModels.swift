import Foundation

enum ActivityCategory: String, Codable, CaseIterable, Identifiable {
    case session = "Sessions"
    case system = "System"
    case assertion = "Assertions"
    case download = "Downloads"

    var id: String { rawValue }
}

enum ActivityType: String, Codable {
    case sessionStarted
    case sessionStopped
    case sessionPaused
    case sessionResumed

    case systemSleep
    case systemWake
    case applicationStarted
    case applicationStopped

    case externalAssertionStarted
    case externalAssertionStopped

    case downloadStarted
    case downloadCompleted
    case downloadFailed
    case downloadCancelled

    var category: ActivityCategory {
        switch self {
        case .sessionStarted, .sessionStopped,
             .sessionPaused, .sessionResumed:
            return .session

        case .systemSleep, .systemWake,
             .applicationStarted, .applicationStopped:
            return .system

        case .externalAssertionStarted,
             .externalAssertionStopped:
            return .assertion

        case .downloadStarted, .downloadCompleted,
             .downloadFailed, .downloadCancelled:
            return .download
        }
    }

    var title: String {
        switch self {
        case .sessionStarted:
            return "Sleep prevention started"
        case .sessionStopped:
            return "Sleep prevention stopped"
        case .sessionPaused:
            return "Sleep prevention paused"
        case .sessionResumed:
            return "Sleep prevention resumed"
        case .systemSleep:
            return "System entered sleep"
        case .systemWake:
            return "System woke up"
        case .applicationStarted:
            return "KeepAwake launched"
        case .applicationStopped:
            return "KeepAwake terminated"
        case .externalAssertionStarted:
            return "External assertion detected"
        case .externalAssertionStopped:
            return "External assertion released"
        case .downloadStarted:
            return "Download started"
        case .downloadCompleted:
            return "Download completed"
        case .downloadFailed:
            return "Download failed"
        case .downloadCancelled:
            return "Download cancelled"
        }
    }

    var icon: String {
        switch self {
        case .sessionStarted, .sessionResumed:
            return "power"
        case .sessionStopped:
            return "stop.circle"
        case .sessionPaused:
            return "pause.circle"
        case .systemSleep:
            return "moon.fill"
        case .systemWake:
            return "sun.max.fill"
        case .applicationStarted:
            return "app.badge"
        case .applicationStopped:
            return "xmark.circle"
        case .externalAssertionStarted:
            return "terminal.fill"
        case .externalAssertionStopped:
            return "terminal"
        case .downloadStarted:
            return "arrow.down.circle"
        case .downloadCompleted:
            return "checkmark.circle.fill"
        case .downloadFailed:
            return "exclamationmark.circle.fill"
        case .downloadCancelled:
            return "xmark.circle"
        }
    }
}

struct ActivityEvent: Identifiable, Codable {
    var id = UUID()
    var timestamp = Date()

    let type: ActivityType
    let detail: String
}

struct ActivityInterval: Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

struct DailyActivity: Identifiable {
    var id: Date { date }

    let date: Date
    let duration: TimeInterval

    var hours: Double {
        duration / 3600
    }
}

enum ActivityPeriod: Int, CaseIterable, Identifiable {
    case today = 1
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return calendar.date(
            byAdding: .day,
            value: -(rawValue - 1),
            to: today
        ) ?? today
    }
}

struct ActivityAnalytics {
    var awakeDuration: TimeInterval = 0
    var sessionCount = 0
    var sleepCount = 0
    var wakeCount = 0
    var completedDownloads = 0
    var failedDownloads = 0

    var dailyActivity: [DailyActivity] = []

    var formattedAwakeDuration: String {
        let hours = awakeDuration / 3600
        return String(format: "%.1f h", hours)
    }
}