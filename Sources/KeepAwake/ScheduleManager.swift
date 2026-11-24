import Foundation

/// Keeps the Mac awake during set hours on set days.
@MainActor
final class ScheduleManager: ObservableObject {
    enum Days: String, CaseIterable, Identifiable {
        case weekdays
        case everyDay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekdays: return "Weekdays"
            case .everyDay: return "Every Day"
            }
        }
    }

    @Published var isEnabled: Bool { didSet { settingsChanged() } }
    @Published var days: Days { didSet { settingsChanged() } }
    /// Hour the schedule starts, 0 to 23.
    @Published var startHour: Int { didSet { settingsChanged() } }
    /// Hour the schedule ends, 0 to 23. If it is earlier than the start
    /// hour, the schedule runs overnight.
    @Published var endHour: Int { didSet { settingsChanged() } }

    private let sleepManager: SleepManager
    private var timer: Timer?

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager

        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "scheduleEnabled")
        days = Days(rawValue: defaults.string(forKey: "scheduleDays") ?? "") ?? .weekdays
        startHour = (defaults.object(forKey: "scheduleStartHour") as? Int) ?? 9
        endHour = (defaults.object(forKey: "scheduleEndHour") as? Int) ?? 18

        let newTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer

        check()
    }

    /// Text for an hour, such as "09:00".
    static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func settingsChanged() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: "scheduleEnabled")
        defaults.set(days.rawValue, forKey: "scheduleDays")
        defaults.set(startHour, forKey: "scheduleStartHour")
        defaults.set(endHour, forKey: "scheduleEndHour")
        check()
    }

    private func check() {
        if isEnabled, isInSchedule(at: Date()) {
            sleepManager.setSchedule(endText: Self.hourLabel(endHour))
        } else {
            sleepManager.setSchedule(endText: nil)
        }
    }

    private func isInSchedule(at date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)

        if startHour == endHour {
            // Same start and end hour means the whole day.
            return isAllowedDay(date)
        }
        if startHour < endHour {
            return isAllowedDay(date) && hour >= startHour && hour < endHour
        }
        // Overnight: the evening part belongs to today, the morning part
        // to the day it started on.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        return (isAllowedDay(date) && hour >= startHour)
            || (isAllowedDay(yesterday) && hour < endHour)
    }

    private func isAllowedDay(_ date: Date) -> Bool {
        switch days {
        case .everyDay:
            return true
        case .weekdays:
            return !Calendar.current.isDateInWeekend(date)
        }
    }
}