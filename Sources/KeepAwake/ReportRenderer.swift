import Foundation
import AppKit
import CoreGraphics

@MainActor
enum ReportRenderer {
    static func render(
        _ report: PowerReport,
        format: ReportFormat
    ) throws -> Data {
        switch format {
        case .pdf:
            return try pdf(report)

        case .html:
            return Data(html(report).utf8)

        case .json:
            let encoder = JSONEncoder()

            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            encoder.dateEncodingStrategy = .iso8601

            return try encoder.encode(report)

        case .text:
            return Data(text(report).utf8)
        }
    }

    // MARK: - Plain text

    static func text(
        _ report: PowerReport
    ) -> String {
        var lines = [
            "KEEPAWAKE",
            "System Power & Activity Report",
            String(repeating: "=", count: 60),

            "Generated: \(report.generatedAt.formatted())",
            "Version: \(report.appVersion)",

            "Privacy protected: " +
                (report.privacyProtected ? "Yes" : "No"),

            ""
        ]

        for section in report.sections {
            lines.append(section.type.rawValue.uppercased())

            lines.append(
                String(repeating: "-", count: 60)
            )

            for field in section.fields {
                lines.append(
                    "\(field.label): \(field.value)"
                )
            }

            for table in section.tables {
                lines.append("")
                lines.append(
                    table.headers.joined(
                        separator: " | "
                    )
                )

                for row in table.rows {
                    lines.append(
                        row.joined(separator: " | ")
                    )
                }
            }

            for paragraph in section.paragraphs {
                lines.append("")
                lines.append(paragraph)
            }

            for finding in section.findings {
                lines.append("")

                lines.append(
                    "[\(finding.severity.rawValue)] " +
                    finding.title
                )

                lines.append(finding.message)
            }

            lines.append("")
        }

        lines.append(
            "Generated locally by KeepAwake."
        )

        return lines.joined(separator: "\n")
    }

    // MARK: - HTML

    static func html(
        _ report: PowerReport
    ) -> String {
        var body = ""

        for (index, section) in report.sections.enumerated() {
            body += """
            <section>
                <h2>
                    <span class="number">
                        \(String(format: "%02d", index + 1))
                    </span>
                    \(escape(section.type.rawValue))
                </h2>
            """

            if !section.fields.isEmpty {
                body += "<table class=\"fields\">"

                for field in section.fields {
                    body += """
                    <tr>
                        <th>\(escape(field.label))</th>
                        <td>\(escape(field.value))</td>
                    </tr>
                    """
                }

                body += "</table>"
            }

            for table in section.tables {
                body += "<table><thead><tr>"

                for header in table.headers {
                    body += "<th>\(escape(header))</th>"
                }

                body += "</tr></thead><tbody>"

                for row in table.rows {
                    body += "<tr>"

                    for cell in row {
                        body += "<td>\(escape(cell))</td>"
                    }

                    body += "</tr>"
                }

                body += "</tbody></table>"
            }

            for paragraph in section.paragraphs {
                body += """
                <pre>\(escape(paragraph))</pre>
                """
            }

            for finding in section.findings {
                let cssClass: String

                switch finding.severity {
                case .critical:
                    cssClass = "critical"

                case .warning:
                    cssClass = "warning"

                case .success:
                    cssClass = "success"

                case .info:
                    cssClass = "info"
                }

                body += """
                <div class="finding \(cssClass)">
                    <strong>
                        \(escape(finding.title))
                    </strong>
                    <p>\(escape(finding.message))</p>
                </div>
                """
            }

            body += "</section>"
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport"
              content="width=device-width, initial-scale=1">
        <title>KeepAwake System Report</title>
        <style>
        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            background: #f1f5f9;
            color: #1e293b;
            font: 13px -apple-system,
                BlinkMacSystemFont, sans-serif;
            line-height: 1.6;
        }

        main {
            max-width: 1000px;
            margin: 32px auto;
            padding: 40px;
            background: white;
            border: 1px solid #e2e8f0;
            border-radius: 10px;
        }

        header {
            border-bottom: 3px solid #2563eb;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }

        h1 {
            margin: 0;
            font-size: 32px;
            letter-spacing: -1px;
        }

        .subtitle {
            font-size: 17px;
            color: #64748b;
        }

        .metadata {
            color: #64748b;
            font-size: 12px;
            margin-top: 12px;
        }

        section {
            margin: 28px 0;
        }

        h2 {
            font-size: 17px;
            margin-bottom: 12px;
        }

        .number {
            color: #2563eb;
            margin-right: 8px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin: 12px 0;
            table-layout: auto;
        }

        th, td {
            padding: 9px 12px;
            text-align: left;
            vertical-align: top;
            border-bottom: 1px solid #e2e8f0;
            overflow-wrap: anywhere;
        }

        thead th {
            background: #f1f5f9;
            font-weight: 600;
        }

        .fields th {
            width: 32%;
            color: #64748b;
            font-weight: 500;
        }

        pre {
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            background: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            padding: 14px;
            font: 11px monospace;
        }

        .finding {
            padding: 12px 16px;
            margin: 8px 0;
            border-left: 3px solid #64748b;
            background: #f8fafc;
        }

        .finding p {
            margin: 5px 0 0;
        }

        .warning {
            background: #fffbeb;
            border-color: #d97706;
        }

        .critical {
            background: #fef2f2;
            border-color: #dc2626;
        }

        .success {
            background: #f0fdf4;
            border-color: #16a34a;
        }

        .info {
            background: #eff6ff;
            border-color: #2563eb;
        }

        footer {
            margin-top: 32px;
            padding-top: 16px;
            border-top: 1px solid #e2e8f0;
            color: #64748b;
            font-size: 11px;
        }

        @media print {
            body {
                background: white;
            }

            main {
                margin: 0;
                padding: 0;
                border: none;
            }

            tr, .finding {
                break-inside: avoid;
            }

            thead {
                display: table-header-group;
            }
        }
        </style>
        </head>

        <body>
        <main>
            <header>
                <h1>KeepAwake</h1>

                <div class="subtitle">
                    System Power &amp; Activity Report
                </div>

                <div class="metadata">
                    Generated:
                    \(escape(report.generatedAt.formatted()))
                    <br>
                    Version:
                    \(escape(report.appVersion))
                    <br>
                    Privacy protected:
                    \(report.privacyProtected ? "Yes" : "No")
                </div>
            </header>

            \(body)

            <footer>
                Generated locally by KeepAwake.
                This report represents a point-in-time
                diagnostic snapshot.
            </footer>
        </main>
        </body>
        </html>
        """
    }

    // MARK: - PDF

    static func pdf(
        _ report: PowerReport
    ) throws -> Data {
        let content = NSMutableAttributedString(
            string: ""
        )

        func append(
            _ text: String,
            size: CGFloat = 10,
            weight: NSFont.Weight = .regular,
            color: NSColor = .black,
            spacing: CGFloat = 5
        ) {
            let paragraph = NSMutableParagraphStyle()

            paragraph.paragraphSpacing = spacing
            paragraph.lineSpacing = 2
            paragraph.lineBreakMode = .byWordWrapping

            content.append(
                NSAttributedString(
                    string: text + "\n",
                    attributes: [
                        .font: NSFont.systemFont(
                            ofSize: size,
                            weight: weight
                        ),

                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                )
            )
        }

        let blue = NSColor(
            red: 0.145,
            green: 0.388,
            blue: 0.922,
            alpha: 1
        )

        let gray = NSColor(
            white: 0.35,
            alpha: 1
        )

        append(
            "KeepAwake",
            size: 28,
            weight: .bold,
            color: blue
        )

        append(
            "System Power & Activity Report",
            size: 16,
            weight: .medium
        )

        append(
            "Generated: \(report.generatedAt.formatted())",
            color: gray
        )

        append(
            "Version: \(report.appVersion)",
            color: gray
        )

        append(
            "Privacy protected: " +
            (report.privacyProtected ? "Yes" : "No"),
            color: gray,
            spacing: 20
        )

        for (index, section) in report.sections.enumerated() {
            append(
                "\(index + 1). \(section.type.rawValue)",
                size: 15,
                weight: .semibold,
                color: blue,
                spacing: 10
            )

            for field in section.fields {
                append(
                    "\(field.label): \(field.value)"
                )
            }

            for table in section.tables {
                if table.rows.isEmpty {
                    append(
                        "No entries",
                        color: gray
                    )

                    continue
                }

                for row in table.rows {
                    let entries = zip(
                        table.headers,
                        row
                    )
                    .map {
                        "\($0.0): \($0.1)"
                    }

                    append(
                        entries.joined(
                            separator: "\n"
                        ),
                        size: 9,
                        spacing: 10
                    )
                }
            }

            for paragraph in section.paragraphs {
                append(
                    paragraph,
                    size: 9,
                    color: gray,
                    spacing: 10
                )
            }

            for finding in section.findings {
                let color: NSColor

                switch finding.severity {
                case .critical:
                    color = .systemRed

                case .warning:
                    color = .systemOrange

                case .success:
                    color = .systemGreen

                case .info:
                    color = blue
                }

                append(
                    "[\(finding.severity.rawValue)] " +
                    finding.title,
                    size: 11,
                    weight: .semibold,
                    color: color
                )

                append(finding.message)
            }

            append("", spacing: 12)
        }

        let pageSize = CGSize(
            width: 595.28,
            height: 841.89
        )

        let margin: CGFloat = 42

        let contentSize = CGSize(
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2 - 25
        )

        let storage = NSTextStorage(
            attributedString: content
        )

        let layout = NSLayoutManager()

        storage.addLayoutManager(layout)

        let data = NSMutableData()

        guard let consumer = CGDataConsumer(
            data: data as CFMutableData
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var mediaBox = CGRect(
            origin: .zero,
            size: pageSize
        )

        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var pageNumber = 0
        var renderedGlyphs = 0

        while renderedGlyphs < layout.numberOfGlyphs {
            let container = NSTextContainer(
                containerSize: contentSize
            )

            container.lineFragmentPadding = 0

            layout.addTextContainer(container)

            layout.ensureLayout(for: container)

            let range = layout.glyphRange(
                for: container
            )

            guard range.length > 0 else {
                context.closePDF()
                throw CocoaError(.fileWriteUnknown)
            }

            pageNumber += 1

            context.beginPDFPage(nil)

            context.saveGState()

            context.translateBy(
                x: 0,
                y: pageSize.height
            )

            context.scaleBy(
                x: 1,
                y: -1
            )

            NSGraphicsContext.saveGraphicsState()

            NSGraphicsContext.current =
                NSGraphicsContext(
                    cgContext: context,
                    flipped: true
                )

            layout.drawBackground(
                forGlyphRange: range,
                at: CGPoint(
                    x: margin,
                    y: margin
                )
            )

            layout.drawGlyphs(
                forGlyphRange: range,
                at: CGPoint(
                    x: margin,
                    y: margin
                )
            )

            let footer =
                "KeepAwake System Report  •  Page \(pageNumber)"

            (footer as NSString).draw(
                at: CGPoint(
                    x: margin,
                    y: pageSize.height - margin
                ),
                withAttributes: [
                    .font: NSFont.systemFont(
                        ofSize: 8
                    ),

                    .foregroundColor: gray
                ]
            )

            NSGraphicsContext.restoreGraphicsState()

            context.restoreGState()
            context.endPDFPage()

            renderedGlyphs = NSMaxRange(range)
        }

        context.closePDF()

        return data as Data
    }

    // MARK: - HTML escaping

    private static func escape(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(
                of: "&",
                with: "&amp;"
            )
            .replacingOccurrences(
                of: "<",
                with: "&lt;"
            )
            .replacingOccurrences(
                of: ">",
                with: "&gt;"
            )
            .replacingOccurrences(
                of: "\"",
                with: "&quot;"
            )
            .replacingOccurrences(
                of: "'",
                with: "&#39;"
            )
    }
}