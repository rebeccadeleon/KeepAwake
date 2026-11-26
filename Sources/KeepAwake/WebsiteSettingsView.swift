import SwiftUI

struct WebsiteSettingsView: View {
    @ObservedObject var manager: WebsiteMonitor

    @State private var name = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Enable website monitoring",
                isOn: $manager.isEnabled
            )

            Toggle(
                "Keep Mac awake while monitoring",
                isOn: $manager.keepAwake
            )
            .disabled(!manager.isEnabled)

            HStack {
                Text("Check interval")

                Spacer()

                Picker(
                    "",
                    selection: $manager.checkInterval
                ) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack {
                Text("Slow response threshold")

                Spacer()

                TextField(
                    "Milliseconds",
                    value: $manager.slowThreshold,
                    format: .number
                )
                .frame(width: 80)

                Text("ms")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                TextField("Name", text: $name)
                    .frame(width: 110)

                TextField("HTTPS URL", text: $url)

                Button {
                    manager.add(
                        name: name,
                        url: url
                    )

                    name = ""
                    url = ""
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(
                    !url.lowercased().hasPrefix("https://")
                )
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(manager.targets) { target in
                        websiteRow(target)
                    }
                }
            }

            HStack {
                Text("\(manager.targets.count) websites")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Check Now") {
                    Task {
                        await manager.checkAll()
                    }
                }
                .disabled(
                    !manager.isEnabled ||
                    manager.isChecking
                )
            }
        }
        .padding(16)
    }

    private func websiteRow(
        _ target: WebsiteTarget
    ) -> some View {
        let result = manager.results[target.id]

        return HStack(spacing: 10) {
            Circle()
                .fill(statusColor(result?.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(.system(
                        size: 13,
                        weight: .medium
                    ))

                Text(target.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let result {
                    Text(
                        "\(result.status.rawValue) · " +
                        "HTTP \(result.statusCode.map { String($0) } ?? "—")"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        statusColor(result.status)
                    )
                }
            }

            Spacer()

            if let latency = result?.latency {
                Text(
                    "\(Int(latency.rounded())) ms"
                )
                .font(.system(
                    size: 12,
                    design: .monospaced
                ))
            }

            Toggle(
                "",
                isOn: Binding(
                    get: {
                        target.isEnabled
                    },
                    set: {
                        manager.setEnabled(
                            target.id,
                            enabled: $0
                        )
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                manager.remove(target.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func statusColor(
        _ status: WebsiteStatus?
    ) -> Color {
        switch status {
        case .online:
            return .green

        case .slow:
            return .orange

        case .offline:
            return .red

        case .unknown, nil:
            return .secondary
        }
    }
}