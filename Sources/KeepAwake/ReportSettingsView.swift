import SwiftUI
import AppKit

struct ReportSettingsView: View {
    @ObservedObject var manager: ReportManager

    @State private var showPreview = false

    private let columns = [
        GridItem(
            .flexible(),
            alignment: .leading
        ),

        GridItem(
            .flexible(),
            alignment: .leading
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    formatSection
                    sectionsSection
                    privacySection
                    statusSection
                }
            }

            Divider()

            footer
        }
        .padding(16)
        .sheet(isPresented: $showPreview) {
            ReportPreviewView(
                manager: manager
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("System Power Report")
                    .font(.system(
                        size: 18,
                        weight: .semibold
                    ))

                Text(
                    "Create a snapshot of your Mac's current power status."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXPORT FORMAT")
                .font(.system(
                    size: 10,
                    weight: .semibold
                ))
                .foregroundStyle(.secondary)

            Picker(
                "",
                selection: $manager.options.format
            ) {
                ForEach(
                    ReportFormat.allCases
                ) { format in
                    Text(format.rawValue)
                        .tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var sectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REPORT SECTIONS")
                    .font(.system(
                        size: 10,
                        weight: .semibold
                    ))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Select All") {
                    manager.options.sections = Set(
                        ReportSectionType.allCases.filter {
                            !manager.options.protectPrivacy ||
                            $0 != .raw
                        }
                    )
                }
                .buttonStyle(.plain)

                Button("Clear") {
                    manager.options.sections = []
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(
                columns: columns,
                spacing: 12
            ) {
                ForEach(
                    ReportSectionType.allCases
                ) { section in
                    Toggle(
                        isOn: sectionBinding(section)
                    ) {
                        Label(
                            section.rawValue,
                            systemImage: section.icon
                        )
                        .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(
                        manager.options.protectPrivacy &&
                        section == .raw
                    )
                }
            }
        }
        .padding(12)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "Protect sensitive information",
                isOn: $manager.options.protectPrivacy
            )
            .onChange(
                of: manager.options.protectPrivacy
            ) { enabled in
                if enabled {
                    manager.options.sections.remove(.raw)
                }
            }

            Text(
                "Redacts private URLs, download file names, " +
                "assertion reasons and selected diagnostic details."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !manager.options.protectPrivacy {
                Label(
                    "Reports may contain sensitive information.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let error = manager.error {
            Label(
                error,
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.red)
        }

        if let url = manager.lastSavedURL {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                VStack(alignment: .leading) {
                    Text("Report saved")
                        .font(.system(
                            size: 12,
                            weight: .medium
                        ))

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open") {
                    NSWorkspace.shared.open(url)
                }

                Button("Show in Finder") {
                    NSWorkspace.shared
                        .activateFileViewerSelecting(
                            [url]
                        )
                }
            }
            .padding(10)
            .background(
                Color.green.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
    }

    private var footer: some View {
        HStack {
            if manager.isGenerating {
                ProgressView()
                    .controlSize(.small)

                Text("Collecting diagnostic information...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    "\(manager.options.sections.count) sections selected"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Preview") {
                Task {
                    await manager.generate()

                    if manager.report != nil {
                        showPreview = true
                    }
                }
            }

            Button("Generate Report") {
                Task {
                    await manager.generate()
                    await manager.save()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(
            manager.isGenerating ||
            manager.options.sections.isEmpty
        )
    }

    private func sectionBinding(
        _ section: ReportSectionType
    ) -> Binding<Bool> {
        Binding(
            get: {
                manager.options.sections.contains(
                    section
                )
            },

            set: { enabled in
                if enabled {
                    manager.options.sections.insert(
                        section
                    )
                } else {
                    manager.options.sections.remove(
                        section
                    )
                }
            }
        )
    }
}