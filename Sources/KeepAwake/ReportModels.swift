import Foundation
import UniformTypeIdentifiers

enum ReportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case html = "HTML"
    case json = "JSON"
    case text = "Text"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .html: return "html"
        case .json: return "json"
        case .text: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .html: return .html
        case .json: return .json
        case .text: return .plainText
        }
    }
}

enum ReportSectionType: String, CaseIterable, Identifiable, Codable {
    case system = "System Information"
    case battery = "Battery & Power"
    case session = "KeepAwake Session"
    case assertions = "Sleep Assertions"
    case activity = "Activity & Analytics"
    case powerConfiguration = "Power Configuration"
    case applications = "Application Watcher"
    case schedule = "Schedules"
    case downloads = "Downloads"
    case electricity = "Electricity Prices"
    case websites = "Website Monitoring"
    case diagnostics = "Diagnostic Findings"
    case raw = "Raw Diagnostic Data"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "desktopcomputer"
        case .battery: return "battery.75percent"
        case .session: return "power"
        case .assertions: return "waveform.path"
        case .activity: return "chart.bar.xaxis"
        case .powerConfiguration: return "bolt.circle"
        case .applications: return "app.badge"
        case .schedule: return "calendar"
        case .downloads: return "arrow.down.circle"
        case .electricity: return "bolt"
        case .websites: return "globe"
        case .diagnostics: return "stethoscope"
        case .raw: return "terminal"
        }
    }
}

struct ReportOptions {
    var format: ReportFormat = .pdf

    var sections: Set<ReportSectionType> = Set(
        ReportSectionType.allCases.filter {
            $0 != .raw
        }
    )

    var protectPrivacy = true
}

struct ReportField: Codable {
    let label: String
    let value: String
}

struct ReportTable: Codable {
    let headers: [String]
    let rows: [[String]]
}

enum DiagnosticSeverity: String, Codable {
    case info = "Information"
    case warning = "Warning"
    case critical = "Critical"
    case success = "Normal"
}

struct DiagnosticFinding: Codable {
    let severity: DiagnosticSeverity
    let title: String
    let message: String
}

struct ReportSection: Codable, Identifiable {
    let type: ReportSectionType

    var fields: [ReportField] = []
    var tables: [ReportTable] = []
    var paragraphs: [String] = []
    var findings: [DiagnosticFinding] = []

    var id: String {
        type.rawValue
    }
}

struct PowerReport: Codable {
    let generatedAt: Date
    let appVersion: String
    let privacyProtected: Bool

    var sections: [ReportSection]
}