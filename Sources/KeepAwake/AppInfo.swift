import Foundation

enum AppInfo {
    static let name = "KeepAwake"

    static let description = "KeepAwake is an intelligent macOS sleep prevention / power management utility featuring customizable sessions, application-based rules, automatic schedules, battery protection, download management, website monitoring, electricity price integration, real-time sleep assertion monitoring, and comprehensive system diagnostics / reports."

    static let version =
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.0"

    static let build =
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"

    static let bundleIdentifier =
        Bundle.main.bundleIdentifier ?? ""
}