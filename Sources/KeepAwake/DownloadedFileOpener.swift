import Foundation
import AppKit
import UniformTypeIdentifiers
import PDFKit
import ImageIO

@MainActor
enum DownloadedFileOpener {
    enum OpenError: LocalizedError {
        case missingFile
        case unsupportedDocument
        case invalidDocument
        case previewUnavailable
        case openingFailed

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return "The downloaded file no longer exists."

            case .unsupportedDocument:
                return "Automatic opening is supported only for PDF documents and common image formats."

            case .invalidDocument:
                return "The file does not contain a valid supported document."

            case .previewUnavailable:
                return "Preview could not be located."

            case .openingFailed:
                return "macOS could not open the file."
            }
        }
    }

    private static let supportedExtensions: Set<String> = [
        "pdf",
        "png",
        "jpg",
        "jpeg",
        "heic",
        "tiff",
        "tif",
        "gif",
        "bmp"
    ]

    static func validateFile(_ url: URL) throws {
        let values = try url.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        )

        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw OpenError.missingFile
        }
    }

    static func validateDocument(_ url: URL) throws {
        try validateFile(url)

        let fileExtension = url.pathExtension.lowercased()

        guard supportedExtensions.contains(fileExtension) else {
            throw OpenError.unsupportedDocument
        }

        if fileExtension == "pdf" {
            guard let document = PDFDocument(url: url),
                  document.pageCount > 0 else {
                throw OpenError.invalidDocument
            }
        } else {
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                nil
            ),
            CGImageSourceGetCount(source) > 0 else {
                throw OpenError.invalidDocument
            }
        }
    }

    static func open(
        _ url: URL,
        application: DownloadOpenApplication,
        automatic: Bool = false
    ) async throws {
        try validateFile(url)

        if automatic || application == .preview {
            try validateDocument(url)
        }

        if !automatic {
            let alert = NSAlert()

            alert.messageText = "Open downloaded file?"
            alert.informativeText = url.lastPathComponent

            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        switch application {
        case .systemDefault:
            guard NSWorkspace.shared.open(url) else {
                throw OpenError.openingFailed
            }

        case .preview:
            guard let previewURL =
                NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.Preview"
                ) else {
                throw OpenError.previewUnavailable
            }

            let configuration =
                NSWorkspace.OpenConfiguration()

            configuration.activates = true

            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: previewURL,
                configuration: configuration
            )
        }
    }

    static func reveal(_ url: URL) throws {
        try validateFile(url)

        NSWorkspace.shared.activateFileViewerSelecting(
            [url]
        )
    }
}