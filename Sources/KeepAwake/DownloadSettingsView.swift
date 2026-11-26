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
            }

            Spacer()

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