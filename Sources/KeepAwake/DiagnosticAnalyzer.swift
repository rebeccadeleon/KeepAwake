import Foundation

@MainActor
enum DiagnosticAnalyzer {
    static func analyze(
        sleep: SleepManager,
        battery: BatteryMonitor,
        assertions: AssertionMonitor,
        downloads: DownloadManager,
        electricity: ElectricityPriceManager,
        websites: WebsiteMonitor
    ) -> [DiagnosticFinding] {
        var findings: [DiagnosticFinding] = []

        if let error = sleep.assertionError {
            findings.append(
                DiagnosticFinding(
                    severity: .critical,
                    title: "Sleep assertion failure",
                    message: error
                )
            )
        }

        if assertions.isEnabled {
            if let error = assertions.error {
                findings.append(
                    DiagnosticFinding(
                        severity: .warning,
                        title: "Assertion monitoring unavailable",
                        message: error
                    )
                )
            } else if assertions.lastUpdated == nil {
                findings.append(
                    DiagnosticFinding(
                        severity: .info,
                        title: "Assertion data unavailable",
                        message:
                            "No successful assertion snapshot has been collected."
                    )
                )
            } else if assertions.hasExternalSleepBlockers {
                findings.append(
                    DiagnosticFinding(
                        severity: .warning,
                        title: "External sleep prevention detected",
                        message:
                            "\(assertions.externalBlockingProcesses.count) " +
                            "external process(es) hold system sleep assertions. " +
                            "Stopping KeepAwake may not allow idle sleep."
                    )
                )
            }
        }

        if !assertions.externalDisplayBlockers.isEmpty {
            findings.append(
                DiagnosticFinding(
                    severity: .warning,
                    title: "External display sleep assertions",
                    message:
                        "Other processes may prevent automatic display sleep."
                )
            )
        }

        if sleep.isPausedForLowBattery {
            findings.append(
                DiagnosticFinding(
                    severity: .warning,
                    title: "Low battery protection active",
                    message:
                        "KeepAwake has paused its sleep prevention assertion."
                )
            )
        }

        if battery.hasBattery &&
           battery.pauseOnLowBattery {
            findings.append(
                DiagnosticFinding(
                    severity: .success,
                    title: "Battery protection enabled",
                    message:
                        "Automatic low-battery protection is configured."
                )
            )
        }

        if downloads.activeCount > 0 &&
           !sleep.isActive {
            findings.append(
                DiagnosticFinding(
                    severity: .warning,
                    title: "Downloads without sleep protection",
                    message:
                        "\(downloads.activeCount) active download(s) " +
                        "are running without KeepAwake's sleep assertion."
                )
            )
        }

        let failedDownloads = downloads.items.filter {
            $0.state == .failed
        }

        if !failedDownloads.isEmpty {
            findings.append(
                DiagnosticFinding(
                    severity: .warning,
                    title: "Failed downloads",
                    message:
                        "\(failedDownloads.count) download(s) failed."
                )
            )
        }

        if electricity.isEnabled {
            if let price = electricity.currentPrice {
                if price.validUntil <= Date() {
                    findings.append(
                        DiagnosticFinding(
                            severity: .warning,
                            title: "Electricity price expired",
                            message:
                                "Current price information is no longer valid."
                        )
                    )
                }
            } else {
                findings.append(
                    DiagnosticFinding(
                        severity: .warning,
                        title: "Electricity price unavailable",
                        message:
                            electricity.error ??
                            "No current electricity price is available."
                    )
                )
            }
        }

        if websites.isEnabled {
            let enabledTargets = websites.targets.filter {
                $0.isEnabled
            }

            let offline = enabledTargets.filter {
                websites.results[$0.id]?.status == .offline
            }

            let slow = enabledTargets.filter {
                websites.results[$0.id]?.status == .slow
            }

            if !offline.isEmpty {
                findings.append(
                    DiagnosticFinding(
                        severity: .warning,
                        title: "Website checks failed",
                        message:
                            "\(offline.count) monitored website(s) " +
                            "failed their latest check."
                    )
                )
            }

            if !slow.isEmpty {
                findings.append(
                    DiagnosticFinding(
                        severity: .warning,
                        title: "Slow website responses",
                        message:
                            "\(slow.count) monitored website(s) " +
                            "exceeded the response time threshold."
                    )
                )
            }
        }

        if ProcessInfo.processInfo.thermalState == .critical {
            findings.append(
                DiagnosticFinding(
                    severity: .critical,
                    title: "Critical thermal state",
                    message:
                        "macOS reports a critical thermal condition."
                )
            )
        }

        if findings.isEmpty {
            findings.append(
                DiagnosticFinding(
                    severity: .success,
                    title: "No issues detected",
                    message:
                        "No issues were identified by the available diagnostic rules."
                )
            )
        }

        return findings
    }
}