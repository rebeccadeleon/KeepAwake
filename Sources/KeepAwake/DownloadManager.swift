import Foundation
import Combine

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

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager
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

        let item = DownloadItem(
            id: id,
            url: url,
            fileName: url.lastPathComponent.isEmpty
                ? "Download"
                : url.lastPathComponent
        )

        items.insert(item, at: 0)

        let task = session.downloadTask(
            with: url
        ) { [weak self] temporaryURL, response, error in

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

                    let folder = try FileManager.default.url(
                        for: .downloadsDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )

                    let suggestedName =
                        response?.suggestedFilename
                        ?? url.lastPathComponent

                    let safeName = URL(
                        fileURLWithPath: suggestedName
                    ).lastPathComponent

                    let name = safeName.isEmpty
                        ? "Download"
                        : safeName

                    var target = folder
                        .appendingPathComponent(name)

                    if FileManager.default.fileExists(
                        atPath: target.path
                    ) {
                        target = folder.appendingPathComponent(
                            "\(UUID().uuidString)-\(name)"
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
            \.fractionCompleted,
            options: [.new]
        ) { [weak self] progress, _ in

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
    }

    private func updateAwakeReason() {
        sleepManager.setAutomaticReason(
            .downloads,
            text: activeCount > 0
                ? "Downloading \(activeCount) file(s)"
                : nil
        )
    }
}