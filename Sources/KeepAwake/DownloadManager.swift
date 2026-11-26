import Foundation
import Combine
import AppKit

enum DownloadState: String {
    case downloading = "Downloading"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case failed = "Failed"
}

struct DownloadItem: Identifiable {
    let id: UUID
    let url: URL

    var fileName: String
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0

    var state: DownloadState = .downloading
    var error: String?
    var destination: URL?
    var options: DownloadOptions = DownloadOptions()

    var openingError: String? = nil

    var progress: Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(
            Double(receivedBytes) /
            Double(totalBytes),
            1
        )
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private let sleepManager: SleepManager

    private var tasks:
        [UUID: URLSessionDownloadTask] = [:]

    private var observations:
        [UUID: NSKeyValueObservation] = [:]

    private let session = URLSession(
        configuration: .default
    )

    private static let optionsKey =
    "downloads.defaultOptions"

    @Published var options: DownloadOptions =
        DownloadOptions() {
        didSet {
            if let data = try? JSONEncoder().encode(options) {
                UserDefaults.standard.set(
                    data,
                    forKey: Self.optionsKey
                )
            }
        }
    }

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager
        if let data = UserDefaults.standard.data(
            forKey: Self.optionsKey
        ),
        let savedOptions = try? JSONDecoder().decode(
            DownloadOptions.self,
            from: data
        ) {
            options = savedOptions
        }
    }

    func chooseDestinationDirectory() {
        let panel = NSOpenPanel()

        panel.title = "Choose Download Location"
        panel.prompt = "Select"

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.directoryURL = URL(
            fileURLWithPath: options.destinationDirectory,
            isDirectory: true
        )

        if panel.runModal() == .OK,
        let url = panel.url {
            options.destinationDirectory = url.path
        }
    }

    var activeCount: Int {
        items.filter {
            $0.state == .downloading
        }.count
    }

    func start(_ urlString: String) {
        guard let url = URL(
            string: urlString.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ),
        url.scheme?.lowercased() == "https",
        url.host != nil else {
            return
        }

        let id = UUID()

        let downloadOptions = options

        var item = DownloadItem(
            id: id,
            url: url,
            fileName: url.lastPathComponent.isEmpty
                ? "Download"
                : url.lastPathComponent
        )
        item.options = downloadOptions
        items.insert(item, at: 0)

        let task: URLSessionDownloadTask =
            session.downloadTask(with: url) { [weak self] temporaryURL, response, error in

            var destination: URL?
            var failure = error?.localizedDescription

            if failure == nil {
                do {
                    guard let http = response
                        as? HTTPURLResponse,
                        (200...299).contains(
                            http.statusCode
                        ),
                        http.url?.scheme == "https",
                        let temporaryURL else {
                        throw URLError(.badServerResponse)
                    }

                    let directory = URL(
                        fileURLWithPath:
                            (downloadOptions.destinationDirectory as NSString)
                                .expandingTildeInPath,
                        isDirectory: true
                    )

                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )

                    // Determine the downloaded filename.
                    let suggestedName =
                        response?.suggestedFilename ?? url.lastPathComponent

                    let sanitizedName = (suggestedName as NSString)
                        .lastPathComponent

                    let fileName = sanitizedName.isEmpty ||
                                sanitizedName == "." ||
                                sanitizedName == ".."
                        ? "Download-\(id.uuidString)"
                        : sanitizedName

                    var target = directory
                        .appendingPathComponent(fileName)

                    // Avoid overwriting an existing file.
                    if FileManager.default.fileExists(
                        atPath: target.path
                    ) {
                        target = directory.appendingPathComponent(
                            "\(UUID().uuidString)-\(fileName)"
                        )
                    }

                    try FileManager.default.moveItem(
                        at: temporaryURL,
                        to: target
                    )

                    destination = target

                } catch {
                    failure = error.localizedDescription
                }
            }

            let finalDestination = destination
            let finalFailure = failure

            Task { @MainActor [weak self] in
                self?.finish(
                    id: id,
                    destination: finalDestination,
                    error: finalFailure
                )
            }
        }

        tasks[id] = task

        observations[id] = task.progress.observe(
            \Progress.fractionCompleted,
            options: NSKeyValueObservingOptions.new
        ) { [weak self] (
            progress: Progress,
            _: NSKeyValueObservedChange<Double>
        ) in

            let received = progress.completedUnitCount
            let total = progress.totalUnitCount

            Task { @MainActor [weak self] in
                self?.updateProgress(
                    id: id,
                    received: received,
                    total: total
                )
            }
        }

        updateAwakeReason()

        task.resume()
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    func remove(_ id: UUID) {
        guard let item = items.first(
            where: { $0.id == id }
        ),
        item.state != .downloading else {
            return
        }

        items.removeAll {
            $0.id == id
        }
    }

    func openFile(
        _ item: DownloadItem,
        application: DownloadOpenApplication? = nil
    ) async {
        guard item.state == .completed,
            let destination = item.destination else {
            return
        }

        do {
            try DownloadedFileOpener.validateDocument(destination)

            try await FileDownloader.downloadAndOpen(
                from: item.url.absoluteString,
                to: destination.path,
                autoOpen: false
            )

            setOpeningError(
                for: item.id,
                message: nil
            )
        } catch {
            setOpeningError(
                for: item.id,
                message: error.localizedDescription
            )
        }
    }

    func revealFile(_ item: DownloadItem) {
        guard item.state == .completed,
            let destination = item.destination else {
            return
        }

        do {
            try DownloadedFileOpener.reveal(destination)

            setOpeningError(
                for: item.id,
                message: nil
            )

        } catch {
            setOpeningError(
                for: item.id,
                message: error.localizedDescription
            )
        }
    }

    private func setOpeningError(
        for id: UUID,
        message: String?
    ) {
        guard let index = items.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }

        items[index].openingError = message
    }

    private func performCompletionActions(
        for id: UUID
    ) {
        guard let item = items.first(
            where: { $0.id == id }
        ),
        item.state == .completed,
        let destination = item.destination else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            var errors: [String] = []

            if item.options.revealWhenCompleted {
                do {
                    try DownloadedFileOpener.reveal(
                        destination
                    )
                } catch {
                    errors.append(
                        error.localizedDescription
                    )
                }
            }

            if item.options.openWhenCompleted {
                do {
                    try await FileDownloader.downloadAndOpen(
                        from: item.url.absoluteString,
                        to: destination.path,
                        autoOpen: true
                    )
                } catch {
                    errors.append(
                        error.localizedDescription
                    )
                }
            }

            self.setOpeningError(
                for: id,
                message: errors.isEmpty
                    ? nil
                    : errors.joined(separator: "\n")
            )
        }
    }

    private func updateProgress(
        id: UUID,
        received: Int64,
        total: Int64
    ) {
        guard let index = items.firstIndex(
            where: { $0.id == id }
        ),
        items[index].state == .downloading else {
            return
        }

        items[index].receivedBytes = received
        items[index].totalBytes = total
    }

    private func finish(
        id: UUID,
        destination: URL?,
        error: String?
    ) {
        let cancelled =
            tasks[id]?.state == .canceling

        observations[id]?.invalidate()
        observations.removeValue(forKey: id)
        tasks.removeValue(forKey: id)

        guard let index = items.firstIndex(
            where: { $0.id == id }
        ) else {
            updateAwakeReason()
            return
        }

        items[index].destination = destination
        items[index].error = error

        if destination != nil {
            items[index].state = .completed

            if items[index].totalBytes > 0 {
                items[index].receivedBytes =
                    items[index].totalBytes
            }
        } else if cancelled {
            items[index].state = .cancelled
        } else {
            items[index].state = .failed
        }

        updateAwakeReason()

        if items[index].state == .completed {
            performCompletionActions(
                for: items[index].id
            )
        }
    }

    var protectedDownloadCount: Int {
        items.filter {
            $0.state == .downloading &&
            $0.options.keepAwake
        }.count
    }

    private func updateAwakeReason() {
        let count = protectedDownloadCount

        sleepManager.setAutomaticReason(
            .downloads,
            text: count > 0
                ? "\(count) protected download(s)"
                : nil
        )
    }
}