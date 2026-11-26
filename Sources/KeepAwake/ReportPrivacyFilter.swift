import Foundation

enum ReportPrivacyFilter {
    static func url(
        _ value: String,
        protected: Bool
    ) -> String {
        guard protected else {
            return value
        }

        guard !value.isEmpty else {
            return "Not configured"
        }

        return "[URL redacted]"
    }

    static func sensitiveText(
        _ value: String,
        protected: Bool
    ) -> String {
        guard protected,
              !value.isEmpty else {
            return value
        }

        return "[Redacted]"
    }

    static func clean(
        _ value: String
    ) -> String {
        var result = value

        let home = FileManager.default
            .homeDirectoryForCurrentUser.path

        if !home.isEmpty {
            result = result.replacingOccurrences(
                of: home,
                with: "~"
            )
        }

        let patterns = [
            #"(?i)https?://[^\s<>"']+"#,
            #"/Users/[^/\s]+"#,
            #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "[Redacted]",
                options: .regularExpression
            )
        }

        return result
    }

    static func apply(
        to report: PowerReport
    ) -> PowerReport {
        guard report.privacyProtected else {
            return report
        }

        var result = report

        result.sections.removeAll {
            $0.type == .raw
        }

        result.sections = result.sections.map {
            section in

            var copy = section

            copy.fields = section.fields.map {
                ReportField(
                    label: clean($0.label),
                    value: clean($0.value)
                )
            }

            copy.tables = section.tables.map {
                ReportTable(
                    headers: $0.headers.map(clean),
                    rows: $0.rows.map {
                        $0.map(clean)
                    }
                )
            }

            copy.paragraphs =
                section.paragraphs.map(clean)

            copy.findings = section.findings.map {
                DiagnosticFinding(
                    severity: $0.severity,
                    title: clean($0.title),
                    message: clean($0.message)
                )
            }

            return copy
        }

        return result
    }
}