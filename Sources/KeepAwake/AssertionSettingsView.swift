import SwiftUI
import AppKit

struct AssertionSettingsView: View {
    @ObservedObject var monitor: AssertionMonitor

    @State private var search = ""
    @State private var category = "All"
    @State private var showOwnProcess = true

    private var filteredAssertions: [SleepAssertion] {
        monitor.assertions.filter { assertion in
            if !showOwnProcess && assertion.isOwnProcess {
                return false
            }

            if category != "All" &&
               assertion.category.rawValue != category {
                return false
            }

            if search.isEmpty {
                return true
            }

            return assertion.processName
                .localizedCaseInsensitiveContains(search) ||
                assertion.name
                .localizedCaseInsensitiveContains(search) ||
                assertion.type
                .localizedCaseInsensitiveContains(search) ||
                String(assertion.pid).contains(search)
        }
    }

    private var filteredProcesses: [AssertionProcess] {
        Dictionary(
            grouping: filteredAssertions,
            by: \.pid
        )
        .map { pid, items in
            AssertionProcess(
                pid: pid,
                name: items.first?.processName ?? "Unknown",
                assertions: items
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls

            Divider()

            statistics

            filters

            if let error = monitor.error {
                Label(
                    error,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            if filteredProcesses.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredProcesses) { process in
                            processRow(process)
                        }
                    }
                }
            }

            Divider()

            footer
        }
        .padding(16)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle(
                    "Enable assertion monitoring",
                    isOn: $monitor.isEnabled
                )

                Spacer()

                Button {
                    Task {
                        await monitor.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(
                    !monitor.isEnabled ||
                    monitor.isRefreshing
                )
                .help("Refresh assertions")
            }

            HStack {
                Text("Refresh interval")

                Spacer()

                Picker(
                    "",
                    selection: $monitor.refreshInterval
                ) {
                    Text("1 second").tag(1.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    // MARK: - Statistics

    private var statistics: some View {
        HStack(spacing: 8) {
            statistic(
                "Processes",
                value: monitor.processes.count,
                color: .primary
            )

            statistic(
                "Assertions",
                value: monitor.assertions.count,
                color: .primary
            )

            statistic(
                "External blockers",
                value: monitor.externalBlockingProcesses.count,
                color: monitor.hasExternalSleepBlockers
                    ? .orange
                    : .green
            )
        }
    }

    private func statistic(
        _ title: String,
        value: Int,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(
                    size: 24,
                    weight: .semibold
                ))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(12)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    "Search processes or assertions...",
                    text: $search
                )
                .textFieldStyle(.plain)

                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 6)
            )

            Picker("", selection: $category) {
                Text("All").tag("All")

                ForEach(
                    AssertionCategory.allCases,
                    id: \.self
                ) { category in
                    Text(category.rawValue)
                        .tag(category.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle(
                "Include KeepAwake's own assertions",
                isOn: $showOwnProcess
            )
            .font(.caption)
        }
    }

    // MARK: - Process row

    private func processRow(
        _ process: AssertionProcess
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                processIcon(process)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(process.name)
                            .font(.system(
                                size: 13,
                                weight: .semibold
                            ))

                        if process.isOwnProcess {
                            Text("Own process")
                                .font(.system(size: 9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Color.accentColor.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(
                        "PID: \(process.pid) · " +
                        "\(process.assertions.count) assertion(s)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if process.preventsSystemSleep {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(.orange)
                        .help("System sleep assertion")
                }

                if process.preventsDisplaySleep {
                    Image(systemName: "display")
                        .foregroundStyle(.blue)
                        .help("Display sleep assertion")
                }
            }

            Divider()

            ForEach(process.assertions) { assertion in
                assertionRow(assertion)
            }
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func assertionRow(
        _ assertion: SleepAssertion
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: assertion.category.icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(assertion.type)
                    .font(.system(
                        size: 11,
                        weight: .medium
                    ))
                    .textSelection(.enabled)

                if !assertion.name.isEmpty {
                    Text(assertion.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Text(assertion.duration)
                .font(.system(
                    size: 11,
                    design: .monospaced
                ))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func processIcon(
        _ process: AssertionProcess
    ) -> some View {
        if let application = NSRunningApplication(
            processIdentifier: process.pid
        ),
        let icon = application.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(
                systemName: process.name == "caffeinate"
                    ? "terminal.fill"
                    : "gearshape.fill"
            )
            .font(.system(size: 23))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(
                monitor.isEnabled
                    ? "No matching assertions"
                    : "Monitoring disabled"
            )
            .font(.headline)

            Text(
                monitor.isEnabled
                    ? "No assertions match the current filters."
                    : "Enable monitoring to inspect sleep assertions."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let updated = monitor.lastUpdated {
                Text(
                    "Last updated: " +
                    updated.formatted(
                        date: .omitted,
                        time: .standard
                    )
                )
            } else {
                Text("Not updated")
            }

            Spacer()

            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Circle()
                .fill(
                    monitor.error != nil
                        ? Color.red
                        : monitor.isEnabled
                            ? Color.green
                            : Color.secondary
                )
                .frame(width: 6, height: 6)

            Text(
                monitor.error != nil
                    ? "Unavailable"
                    : monitor.isEnabled
                        ? "Monitoring"
                        : "Disabled"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}