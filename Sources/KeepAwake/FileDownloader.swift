import Foundation
import AppKit

enum FileDownloader {
    @MainActor
    @discardableResult
    static func downloadAndOpen(
        from urlString: String,
        to path: String,
        autoOpen: Bool = false
    ) async throws -> URL {
        let fileManager = FileManager.default

        let destination = URL(
            fileURLWithPath: (path as NSString)
                .expandingTildeInPath
        )

        var isDirectory: ObjCBool = false

        let exists = fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &isDirectory
        )

        if exists && isDirectory.boolValue {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        if !exists {
            guard let url = URL(string: urlString),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else {
                throw URLError(.badURL)
            }

            // Create parent directory if necessary.
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Download file.
            let (temporaryURL, response) =
                try await URLSession.shared.download(from: url)

            defer {
                try? fileManager.removeItem(at: temporaryURL)
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  httpResponse.url?.scheme?.lowercased() == "https" else {
                throw URLError(.badServerResponse)
            }

            try fileManager.moveItem(
                at: temporaryURL,
                to: destination
            )
        }

        // Restrict Preview opening to supported document types.
        let supportedExtensions: Set<String> = [
            "pdf", "png", "jpg", "jpeg",
            "heic", "tiff", "tif", "gif", "bmp"
        ]

        guard supportedExtensions.contains(
            destination.pathExtension.lowercased()
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        // Confirm before opening unless explicitly requested.
        if !autoOpen {
            let alert = NSAlert()

            alert.messageText = "Open downloaded file?"
            alert.informativeText = destination.lastPathComponent

            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return destination
            }
        }

        // Locate Preview.
        guard let previewURL =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Preview"
            ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        // Wait for Preview to open the file.
        _ = try await NSWorkspace.shared.open(
            [destination],
            withApplicationAt: previewURL,
            configuration: configuration
        )

        return destination
    }
}