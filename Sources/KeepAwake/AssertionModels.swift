import Foundation

enum AssertionCategory: String, CaseIterable {
    case systemSleep = "System Sleep"
    case displaySleep = "Display Sleep"
    case activity = "Activity"
    case other = "Other"

    var icon: String {
        switch self {
        case .systemSleep:
            return "moon.zzz"

        case .displaySleep:
            return "display"

        case .activity:
            return "waveform.path"

        case .other:
            return "gearshape"
        }
    }
}

struct SleepAssertion: Identifiable, Equatable {
    let pid: Int32
    let processName: String
    let assertionID: String
    let duration: String
    let type: String
    let name: String

    var id: String {
        "\(pid):\(assertionID)"
    }

    var isOwnProcess: Bool {
        pid == ProcessInfo.processInfo.processIdentifier
    }

    var category: AssertionCategory {
        switch type {
        case "PreventUserIdleSystemSleep",
             "PreventSystemSleep",
             "NoIdleSleep":
            return .systemSleep

        case "PreventUserIdleDisplaySleep",
             "NoDisplaySleep":
            return .displaySleep

        case "UserIsActive":
            return .activity

        default:
            return .other
        }
    }

    var preventsSystemSleep: Bool {
        category == .systemSleep
    }

    var preventsDisplaySleep: Bool {
        category == .displaySleep
    }
}

struct AssertionProcess: Identifiable {
    let pid: Int32
    let name: String
    let assertions: [SleepAssertion]

    var id: Int32 {
        pid
    }

    var isOwnProcess: Bool {
        pid == ProcessInfo.processInfo.processIdentifier
    }

    var preventsSystemSleep: Bool {
        assertions.contains {
            $0.preventsSystemSleep
        }
    }

    var preventsDisplaySleep: Bool {
        assertions.contains {
            $0.preventsDisplaySleep
        }
    }
}

struct AssertionSnapshot {
    var assertions: [SleepAssertion] = []
    var systemStatus: [String: Int] = [:]
}