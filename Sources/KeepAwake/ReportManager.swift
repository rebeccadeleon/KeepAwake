import Foundation
import Combine
import AppKit

@MainActor
final class ReportManager: ObservableObject {
    @Published private(set) var report: PowerReport?
    @Published private(set) var isGenerating = false
    @Published private(set) var error: String?
    @Published private(set) var lastSavedURL: URL?

    @Published var options = ReportOptions()

    private let sleep: SleepManager
    private let battery: BatteryMonitor
    private let watcher: AppWatcher
    private let schedule: ScheduleManager
    private let assertions: AssertionMonitor
    private let downloads: DownloadManager
    private let electricity: ElectricityPriceManager
    private let websites: WebsiteMonitor
    private let activity: ActivityHistoryManager

    init(
        sleep: SleepManager,
        battery: BatteryMonitor,
        watcher: AppWatcher,
        schedule: ScheduleManager,
        assertions: AssertionMonitor,
        downloads: DownloadManager,
        electricity: ElectricityPriceManager,
        websites: WebsiteMonitor,
        activity: ActivityHistoryManager
    ) {
        self.sleep = sleep
        self.battery = battery
        self.watcher = watcher
        self.schedule = schedule
        self.assertions = assertions
        self.downloads = downloads
        self.electricity = electricity
        self.websites = websites
        self.activity = activity
    }

    func generate() async {
        guard !isGenerating else {
            return
        }

        isGenerating = true
        error = nil

        defer {
            isGenerating = false
        }

        let selected = options.sections
        let privacy = options.protectPrivacy

        if assertions.isEnabled {
            await assertions.refresh()
        }

        var sections: [ReportSection] = []

        for type in ReportSectionType.allCases {
            guard selected.contains(type) else {
                continue
            }

            if privacy && type == .raw {
                continue
            }

            switch type {
            case .system:
                sections.append(
                    ReportSection(
                        type: .system,
                        fields:
                            SystemInfoCollector.systemFields()
                    )
                )

            case .battery:
                sections.append(
                    await batterySection(
                        privacy: privacy
                    )
                )

            case .session:
                sections.append(sessionSection())

            case .assertions:
                sections.append(
                    assertionSection(
                        privacy: privacy
                    )
                )

            case .powerConfiguration:
                sections.append(
                    await powerConfigurationSection()
                )

            case .applications:
                sections.append(applicationSection())

            case .schedule:
                sections.append(scheduleSection())

            case .downloads:
                sections.append(
                    downloadSection(
                        privacy: privacy
                    )
                )

            case .electricity:
                sections.append(
                    electricitySection(
                        privacy: privacy
                    )
                )

            case .websites:
                sections.append(
                    websiteSection(
                        privacy: privacy
                    )
                )

            case .diagnostics:
                sections.append(
                    diagnosticSection(
                        privacy: privacy
                    )
                )

            case .raw:
                sections.append(
                    await rawSection()
                )

            case .activity:
                sections.append(
                    activitySection(privacy: privacy)
                )
            }
        }

        let version = Bundle.main.object(
            forInfoDictionaryKey:
                "CFBundleShortVersionString"
        ) as? String ?? "Unknown"

        let snapshot = PowerReport(
            generatedAt: Date(),
            appVersion: version,
            privacyProtected: privacy,
            sections: sections
        )

        report = ReportPrivacyFilter.apply(
            to: snapshot
        )
    }

    // MARK: - Battery

    private func batterySection(
        privacy: Bool
    ) async -> ReportSection {
        let result = await SystemInfoCollector.command(
            "/usr/bin/pmset",
            arguments: ["-g", "batt"]
        )

        var fields = [
            field(
                "Battery available",
                yesNo(battery.hasBattery)
            ),

            field(
                "Low battery protection",
                yesNo(battery.pauseOnLowBattery)
            ),

            field(
                "Protection threshold",
                "\(battery.effectivePauseThreshold)%"
            ),

            field(
                "Protection active",
                yesNo(sleep.isPausedForLowBattery)
            ),

            field(
                "Resume threshold",
                "\(battery.effectiveResumeThreshold)%"
            ),

            field(
                "AC power only",
                yesNo(battery.acPowerOnly)
            ),

            field(
                "Battery percentage",
                battery.information.map {
                    "\($0.percentage)%"
                } ?? "Unavailable"
            ),

            field(
                "Power source",
                battery.information?.powerSource ??
                    "Unavailable"
            ),

            field(
                "Charging status",
                battery.information?.chargingStatus ??
                    "Unavailable"
            ),

            field(
                "Battery cycle count",
                battery.information?.cycleCount.map {
                    String($0)
                } ?? "Unavailable"
            ),

            field(
                "Estimated battery health",
                battery.information?.healthPercentage.map {
                    String(format: "%.1f%%", $0)
                } ?? "Unavailable"
            ),

            field(
                "Protection reason",
                battery.protectionReason ?? "None"
            ),
        ]

        if result.succeeded {
            let lines = result.output.components(
                separatedBy: .newlines
            )

            if let first = lines.first {
                fields.append(
                    field("Power source", first)
                )
            }

            if let range = result.output.range(
                of: #"\d{1,3}%"#,
                options: .regularExpression
            ) {
                fields.append(
                    field(
                        "Battery charge",
                        String(result.output[range])
                    )
                )
            }
        } else {
            fields.append(
                field(
                    "Battery information",
                    "Unavailable"
                )
            )
        }

        return ReportSection(
            type: .battery,
            fields: fields,
            paragraphs: privacy
                ? []
                : [result.output]
        )
    }

    // MARK: - Session

    private func sessionSection() -> ReportSection {
        var fields = [
            field("Status", sleep.statusText),

            field(
                "Sleep assertion held",
                yesNo(sleep.isActive)
            ),

            field(
                "Manual session",
                yesNo(sleep.isManualActive)
            ),

            field(
                "Remaining time",
                sleep.remainingText ?? "Not applicable"
            ),

            field(
                "Allow display sleep",
                yesNo(sleep.allowDisplaySleep)
            ),

            field(
                "Manually paused",
                yesNo(sleep.isPausedManually)
            )
        ]

        if let endDate = sleep.endDate {
            fields.append(
                field(
                    "Session end",
                    formatDate(endDate)
                )
            )
        }

        let rules = AutomaticAwakeReason.allCases
            .compactMap { reason -> [String]? in
                guard let description =
                    sleep.automaticReasons[reason] else {
                    return nil
                }

                return [
                    reason.rawValue,
                    description
                ]
            }

        return ReportSection(
            type: .session,
            fields: fields,
            tables: rules.isEmpty
                ? []
                : [
                    ReportTable(
                        headers: ["Rule", "Description"],
                        rows: rules
                    )
                ]
        )
    }

    // MARK: - Assertions

    private func assertionSection(
        privacy: Bool
    ) -> ReportSection {
        let rows = assertions.assertions.map {
            assertion in

            [
                assertion.processName,
                String(assertion.pid),
                assertion.type,
                assertion.duration,

                assertion.isOwnProcess
                    ? "KeepAwake"
                    : "External",

                ReportPrivacyFilter.sensitiveText(
                    assertion.name,
                    protected: privacy
                )
            ]
        }

        let systemRows = assertions.systemStatus
            .sorted {
                $0.key < $1.key
            }
            .map {
                [$0.key, String($0.value)]
            }

        return ReportSection(
            type: .assertions,
            fields: [
                field(
                    "Monitoring enabled",
                    yesNo(assertions.isEnabled)
                ),

                field(
                    "Last updated",
                    formatDate(assertions.lastUpdated)
                ),

                field(
                    "External blocking processes",
                    String(
                        assertions
                            .externalBlockingProcesses.count
                    )
                ),

                field(
                    "System idle sleep blocked",
                    assertions.lastUpdated == nil ||
                    assertions.error != nil
                        ? "Unknown"
                        : yesNo(
                            assertions.isSystemSleepBlocked
                        )
                )
            ],
            tables: [
                ReportTable(
                    headers: [
                        "Process",
                        "PID",
                        "Type",
                        "Duration",
                        "Owner",
                        "Reason"
                    ],
                    rows: rows
                ),

                ReportTable(
                    headers: [
                        "System assertion",
                        "Status"
                    ],
                    rows: systemRows
                )
            ]
        )
    }

    // MARK: - Power configuration

    private func powerConfigurationSection()
        async -> ReportSection {

        let result = await SystemInfoCollector.command(
            "/usr/bin/pmset",
            arguments: ["-g", "custom"]
        )

        return ReportSection(
            type: .powerConfiguration,
            fields: [
                field(
                    "Collection status",
                    result.succeeded
                        ? "Available"
                        : "Unavailable"
                )
            ],
            paragraphs: [result.output]
        )
    }

    // MARK: - Applications

    private func applicationSection() -> ReportSection {
        let triggeringApps = self.sleep.triggeringApps

        let rows: [[String]] = watcher.watched
            .sorted {
                $0.value.localizedCaseInsensitiveCompare(
                    $1.value
                ) == .orderedAscending
            }
            .map { app in
                [
                    app.value,
                    app.key,
                    triggeringApps.contains(app.value)
                        ? "Triggering"
                        : "Watched"
                ]
            }

        return ReportSection(
            type: .applications,
            fields: [
                field(
                    "Watched applications",
                    String(watcher.watched.count)
                ),

                field(
                    "Triggering applications",
                    triggeringApps.isEmpty
                        ? "None"
                        : triggeringApps.joined(separator: ", ")
                )
            ],
            tables: [
                ReportTable(
                    headers: [
                        "Application",
                        "Bundle Identifier",
                        "Status"
                    ],
                    rows: rows
                )
            ]
        )
    }

    // MARK: - Schedule

    private func scheduleSection() -> ReportSection {
        ReportSection(
            type: .schedule,
            fields: [
                field(
                    "Enabled",
                    yesNo(schedule.isEnabled)
                ),

                field(
                    "Start hour",
                    String(schedule.startHour)
                ),

                field(
                    "End hour",
                    String(schedule.endHour)
                ),

                field(
                    "Current schedule",
                    sleep.scheduleEndText ?? "Inactive"
                )
            ]
        )
    }

    // MARK: - Downloads

    private func downloadSection(
        privacy: Bool
    ) -> ReportSection {
        let rows = downloads.items.map {
            item in

            [
                privacy
                    ? "[File name redacted]"
                    : item.fileName,

                item.state.rawValue,

                item.totalBytes > 0
                    ? "\(Int(item.progress * 100))%"
                    : "Unknown",

                ByteCountFormatter.string(
                    fromByteCount: item.receivedBytes,
                    countStyle: .file
                ),

                ReportPrivacyFilter.url(
                    item.url.absoluteString,
                    protected: privacy
                ),

                yesNo(item.options.keepAwake),

                yesNo(item.options.openWhenCompleted),

                yesNo(item.options.revealWhenCompleted)
            ]
        }

        return ReportSection(
            type: .downloads,
            fields: [
                field(
                    "Active downloads",
                    String(downloads.activeCount)
                ),

                field(
                    "Total downloads",
                    String(downloads.items.count)
                ),

                field(
                    "Protected downloads",
                    String(downloads.protectedDownloadCount)
                )
            ],
            tables: [
                ReportTable(
                    headers: [
                        "File",
                        "Status",
                        "Progress",
                        "Received",
                        "URL",
                        "Sleep Protection",
                        "Auto Open",
                        "Reveal in Finder"
                    ],
                    rows: rows
                )
            ]
        )
    }

    // MARK: - Electricity

    private func electricitySection(
        privacy: Bool
    ) -> ReportSection {
        var fields = [
            field(
                "Enabled",
                yesNo(electricity.isEnabled)
            ),

            field(
                "Price endpoint",
                ReportPrivacyFilter.url(
                    electricity.endpoint,
                    protected: privacy
                )
            ),

            field(
                "Maximum price",
                String(
                    format: "%.2f",
                    electricity.maximumPrice
                )
            ),

            field(
                "Energy rule active",
                yesNo(electricity.isLowPrice)
            ),

            field(
                "Last checked",
                formatDate(electricity.lastChecked)
            )
        ]

        if let price = electricity.currentPrice {
            let formatted = String(
                format: "%.2f",
                price.price
            )

            fields.append(
                field(
                    "Current price",
                    "\(formatted) \(price.currency)/kWh"
                )
            )

            fields.append(
                field(
                    "Valid until",
                    formatDate(price.validUntil)
                )
            )
        }

        if let error = electricity.error {
            fields.append(
                field(
                    "Error",
                    ReportPrivacyFilter.sensitiveText(
                        error,
                        protected: privacy
                    )
                )
            )
        }

        return ReportSection(
            type: .electricity,
            fields: fields
        )
    }

    // MARK: - Websites

    private func websiteSection(
        privacy: Bool
    ) -> ReportSection {
        let rows = websites.targets.enumerated().map {
            index, target in

            let result = websites.results[target.id]

            let latency = result?.latency.map {
                "\(Int($0.rounded())) ms"
            } ?? "—"

            let statusCode = result?.statusCode.map {
                String($0)
            } ?? "—"

            return [
                privacy
                    ? "Website \(index + 1)"
                    : target.name,

                ReportPrivacyFilter.url(
                    target.url,
                    protected: privacy
                ),

                !target.isEnabled
                    ? "Disabled"
                    : result?.status.rawValue ?? "Waiting",

                statusCode,
                latency,

                formatDate(result?.checkedAt)
            ]
        }

        return ReportSection(
            type: .websites,
            fields: [
                field(
                    "Monitoring enabled",
                    yesNo(websites.isEnabled)
                ),

                field(
                    "Keep Mac awake",
                    yesNo(websites.keepAwake)
                ),

                field(
                    "Check interval",
                    "\(Int(websites.checkInterval)) seconds"
                )
            ],
            tables: [
                ReportTable(
                    headers: [
                        "Website",
                        "URL",
                        "Status",
                        "HTTP",
                        "Latency",
                        "Checked"
                    ],
                    rows: rows
                )
            ]
        )
    }

    // MARK: - Diagnostics

    private func diagnosticSection(
        privacy: Bool
    ) -> ReportSection {
        var findings = DiagnosticAnalyzer.analyze(
            sleep: sleep,
            battery: battery,
            assertions: assertions,
            downloads: downloads,
            electricity: electricity,
            websites: websites
        )

        if privacy {
            findings = findings.map {
                finding in

                let sensitiveTitles = [
                    "Sleep assertion failure",
                    "Assertion monitoring unavailable",
                    "Electricity price unavailable"
                ]

                return DiagnosticFinding(
                    severity: finding.severity,
                    title: finding.title,
                    message: sensitiveTitles.contains(
                        finding.title
                    )
                        ? "Additional error details redacted."
                        : finding.message
                )
            }
        }

        return ReportSection(
            type: .diagnostics,
            findings: findings
        )
    }

    // MARK: - Raw output

    private func rawSection() async -> ReportSection {
        let commands = [
            ["-g", "assertions"],
            ["-g", "custom"],
            ["-g", "batt"],
            ["-g", "sched"],
            ["-g", "therm"]
        ]

        var paragraphs: [String] = []

        for arguments in commands {
            let result = await SystemInfoCollector.command(
                "/usr/bin/pmset",
                arguments: arguments
            )

            paragraphs.append(
                "$ pmset \(arguments.joined(separator: " "))\n" +
                result.output
            )
        }

        return ReportSection(
            type: .raw,
            paragraphs: paragraphs
        )
    }

    private func activitySection(
        privacy: Bool
    ) -> ReportSection {
        activity.refresh()

        let analytics = activity.analytics

        let dailyRows: [[String]] =
            analytics.dailyActivity.map { day in
                [
                    day.date.formatted(
                        date: .abbreviated,
                        time: .omitted
                    ),
                    String(
                        format: "%.2f hours",
                        day.hours
                    )
                ]
            }

        let eventRows: [[String]] =
            activity.events.prefix(100).map { event in
                [
                    event.timestamp.formatted(
                        date: .abbreviated,
                        time: .standard
                    ),
                    event.type.category.rawValue,
                    event.type.title,
                    privacy
                        ? "[Redacted]"
                        : event.detail
                ]
            }

        return ReportSection(
            type: .activity,
            fields: [
                field(
                    "Period",
                    activity.period.title
                ),
                field(
                    "Sleep prevention duration",
                    analytics.formattedAwakeDuration
                ),
                field(
                    "Active intervals",
                    String(analytics.sessionCount)
                ),
                field(
                    "Sleep events",
                    String(analytics.sleepCount)
                ),
                field(
                    "Wake events",
                    String(analytics.wakeCount)
                ),
                field(
                    "Completed downloads",
                    String(analytics.completedDownloads)
                ),
                field(
                    "Failed downloads",
                    String(analytics.failedDownloads)
                )
            ],
            tables: [
                ReportTable(
                    headers: [
                        "Date",
                        "Sleep prevention duration"
                    ],
                    rows: dailyRows
                ),
                ReportTable(
                    headers: [
                        "Timestamp",
                        "Category",
                        "Event",
                        "Detail"
                    ],
                    rows: eventRows
                )
            ]
        )
    }

    // MARK: - Export

    func save() async {
        guard let report else {
            return
        }

        let format = options.format

        let panel = NSSavePanel()

        panel.allowedContentTypes = [
            format.contentType
        ]

        panel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"

        panel.nameFieldStringValue =
            "KeepAwake-Report-" +
            formatter.string(from: report.generatedAt) +
            "." + format.fileExtension

        let response = await withCheckedContinuation {
            continuation in

            panel.begin {
                response in

                continuation.resume(
                    returning: response
                )
            }
        }

        guard response == .OK,
              let url = panel.url else {
            return
        }

        do {
            let data = try ReportRenderer.render(
                report,
                format: format
            )

            try data.write(
                to: url,
                options: .atomic
            )

            lastSavedURL = url
            error = nil

        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func field(
        _ label: String,
        _ value: String
    ) -> ReportField {
        ReportField(
            label: label,
            value: value
        )
    }

    private func yesNo(
        _ value: Bool
    ) -> String {
        value ? "Yes" : "No"
    }

    private func formatDate(
        _ date: Date?
    ) -> String {
        guard let date else {
            return "Unavailable"
        }

        return date.formatted(
            date: .abbreviated,
            time: .standard
        )
    }
}