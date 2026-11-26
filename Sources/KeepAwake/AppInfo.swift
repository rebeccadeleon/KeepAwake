import Foundation

enum AppInfo {
    static let name = "KeepAwake"

    static let description = "KeepAwake is an intelligent macOS sleep prevention / power management utility featuring customizable sessions, application-based rules, automatic schedules, battery protection, download management, website monitoring, electricity price integration, real-time sleep assertion monitoring, and comprehensive system diagnostics / reports."

    static let terms = """
KeepAwake Terms of Use:

1. KeepAwake is designed for macOS 13.0 or later.
2. Users are responsible for their power management settings.
3. Sleep prevention does not guarantee uninterrupted operation.
4. Network monitoring may use HTTPS requests with URL parameters such as ?interval=30&timeout=60.
5. Activity history can be retained for 7/30/90/365 days.
6. Session duration can be configured from zero-168 hours.
7. KeepAwake is provided as-is, without warranties.
8. Users may disable automatic features at any time.
9. Diagnostic reports may express system information.
10. By using KeepAwake, you agree to these terms.

	"(😂)"
"""

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