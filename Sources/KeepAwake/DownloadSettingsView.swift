import SwiftUI
import AppKit

struct DownloadSettingsView: View {
    @ObservedObject var manager: DownloadManager

    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("HTTPS download URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startDownload)

                Button("Download") {
                    startDownload()
                }
                .disabled(
                    !url.lowercased().hasPrefix("https://")
                )
            }

            downloadOptionsSection

            HStack {
                Label(
                    "\(manager.activeCount) active downloads",
                    systemImage: "arrow.down.circle"
                )
                .font(.caption)

                Spacer()

                Button("Open Downloads") {
                    NSWorkspace.shared.open(
                        FileManager.default
                            .homeDirectoryForCurrentUser
                            .appendingPathComponent("Downloads")
                    )
                }
            }

            Divider()

            if manager.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text("No downloads")
                        .font(.headline)

                    Text("Enter an HTTPS file URL to begin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(manager.items) { item in
                            downloadRow(item)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private var downloadOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOWNLOAD OPTIONS")
                .font(.system(
                    size: 10,
                    weight: .semibold
                ))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Save location")
                    .font(.system(size: 12))

                HStack(spacing: 8) {
                    TextField(
                        "Destination",
                        text: $manager.options.destinationDirectory
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        manager.chooseDestinationDirectory()
                    }
                }
            }

            Divider()

            Toggle(
                "Keep Mac awake during download",
                isOn: $manager.options.keepAwake
            )

            Toggle(
                "Open document when completed",
                isOn: $manager.options.openWhenCompleted
            )

            if manager.options.openWhenCompleted {
                Picker(
                    "Open with",
                    selection: $manager.options.openApplication
                ) {
                    ForEach(
                        DownloadOpenApplication.allCases
                    ) { application in
                        Text(application.rawValue)
                            .tag(application)
                    }
                }
                .padding(.leading, 20)

                Text(
                    "Automatic opening applies to PDF " +
                    "documents and supported images."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            }

            Toggle(
                "Reveal in Finder when completed",
                isOn: $manager.options.revealWhenCompleted
            )
        }
        .font(.system(size: 12))
        .padding(12)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func completedDownloadActions(
        _ item: DownloadItem
    ) -> some View {
        HStack(spacing: 10) {
            Menu {
                Button("Open") {
                    Task {
                        await manager.openFile(
                            item,
                            application: .systemDefault
                        )
                    }
                }

                Button("Open in Preview") {
                    Task {
                        await manager.openFile(
                            item,
                            application: .preview
                        )
                    }
                }

                Divider()

                Button("Show in Finder") {
                    manager.revealFile(item)
                }

            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Open downloaded file")

            Button {
                manager.revealFile(item)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

            Button {
                manager.remove(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from download list")
        }
    }

    private func downloadRow(
        _ item: DownloadItem
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if item.state == .downloading {
                    if item.totalBytes > 0 {
                        ProgressView(value: item.progress)
                    } else {
                        ProgressView()
                    }

                    Text(
                        "\(formatBytes(item.receivedBytes)) / " +
                        "\(formatBytes(item.totalBytes))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if item.state == .completed {
                    completedDownloadActions(item)
                }

                Text(item.state.rawValue)
                    .font(.caption)
                    .foregroundStyle(
                        item.state == .completed
                            ? Color.green
                            : Color.secondary
                    )

                if let error = item.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let error = item.openingError {
                    Label(
                        error,
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
            }

            Spacer()

            if item.state == .downloading &&
                item.options.keepAwake {
                Label(
                    "Sleep protection enabled",
                    systemImage: "cup.and.saucer.fill"
                )
                .font(.caption2)
                .foregroundStyle(.green)
            }

            if item.state == .downloading {
                Button {
                    manager.cancel(item.id)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            } else {
                if let destination = item.destination {
                    Button {
                        NSWorkspace.shared
                            .activateFileViewerSelecting(
                                [destination]
                            )
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }

                Button {
                    manager.remove(item.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func startDownload() {
        guard !url.isEmpty else {
            return
        }

        manager.start(url)
        url = ""
    }

    private func formatBytes(
        _ bytes: Int64
    ) -> String {
        guard bytes > 0 else {
            return "—"
        }

        return ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}