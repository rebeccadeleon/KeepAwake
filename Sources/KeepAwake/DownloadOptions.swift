import Foundation

enum DownloadOpenApplication: String, Codable, CaseIterable, Identifiable {
    case systemDefault = "Default Application"
    case preview = "Preview"

    var id: String {
        rawValue
    }
}

struct DownloadOptions: Codable, Equatable, Sendable {
    var destinationDirectory: String =
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .path

    var keepAwake = true

    var openWhenCompleted = false

    var revealWhenCompleted = false

    var openApplication: DownloadOpenApplication = .systemDefault
}