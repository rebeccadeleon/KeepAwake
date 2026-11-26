import SwiftUI
import Charts

struct ActivitySettingsView: View {
    @ObservedObject var manager: ActivityHistoryManager

    @State private var search = ""
    @State private var category: ActivityCategory?
    @State private var showClearConfirmation = false

    private var filteredEvents: [ActivityEvent] {
        manager.events.filter { event in
            let matchesCategory =
                category == nil ||
                event.type.category == category

            let matchesSearch =
                search.isEmpty ||
                event.type.title.localizedCaseInsensitiveContains(
                    search
                ) ||
                event.detail.localizedCaseInsensitiveContains(
                    search
                )

            return matchesCategory && matchesSearch
        }
    }

    private var groupedEvents: [Date: [ActivityEvent]] {
        Dictionary(grouping: filteredEvents) {
            Calendar.current.startOfDay(
                for: $0.timestamp
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    statisticsSection
                    chartSection
                    historySection
                }
                .padding(16)
            }

            Divider()

            footer
                .padding(12)
        }
        .alert(
            "Clear Activity History?",
            isPresented: $showClearConfirmation
        ) {
            Button("Cancel", role: .cancel) {}

            Button("Clear History", role: .destructive) {
                manager.clearHistory()
            }
        } message: {
            Text(
                "All recorded activity and historical " +
                "analytics will be permanently deleted."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 26))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text("Activity & Analytics")
                    .font(.system(
                        size: 16,
                        weight: .semibold
                    ))

                Text("Historical system power activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(
                "",
                selection: $manager.period
            ) {
                ForEach(ActivityPeriod.allCases) {
                    period in

                    Text(period.title)
                        .tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Button {
                manager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh activity")
        }
    }

    // MARK: - Statistics

    private var statisticsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            statisticCard(
                title: "Sleep prevention",
                value: manager.analytics.formattedAwakeDuration,
                icon: "cup.and.saucer.fill",
                color: .blue
            )

            statisticCard(
                title: "Active intervals",
                value: String(
                    manager.analytics.sessionCount
                ),
                icon: "power",
                color: .green
            )

            statisticCard(
                title: "System sleep events",
                value: String(
                    manager.analytics.sleepCount
                ),
                icon: "moon.fill",
                color: .purple
            )

            statisticCard(
                title: "Completed downloads",
                value: String(
                    manager.analytics.completedDownloads
                ),
                icon: "arrow.down.circle.fill",
                color: .orange
            )
        }
    }

    private func statisticCard(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(
                    size: 26,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(14)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.secondary.opacity(0.12)
                )
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Sleep prevention duration")
                .font(.system(
                    size: 13,
                    weight: .semibold
                ))

            Chart(manager.analytics.dailyActivity) {
                activity in

                BarMark(
                    x: .value(
                        "Date",
                        activity.date,
                        unit: .day
                    ),
                    y: .value(
                        "Hours",
                        activity.hours
                    )
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.blue,
                            Color.blue.opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    value in

                    AxisGridLine()

                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text(
                                "\(hours, specifier: "%.0f")h"
                            )
                        }
                    }
                }
            }
            .frame(height: 180)

            Text(
                "Time during which KeepAwake held " +
                "an active sleep prevention assertion."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - History

    private var historySection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Text("Activity history")
                    .font(.system(
                        size: 13,
                        weight: .semibold
                    ))

                Spacer()

                Text(
                    "\(filteredEvents.count) events"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(
                        "Search activity...",
                        text: $search
                    )
                    .textFieldStyle(.plain)

                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(
                                systemName: "xmark.circle.fill"
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(
                    Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )

                Picker(
                    "",
                    selection: $category
                ) {
                    Text("All events")
                        .tag(nil as ActivityCategory?)

                    ForEach(
                        ActivityCategory.allCases
                    ) { category in

                        Text(category.rawValue)
                            .tag(Optional(category))
                    }
                }
                .frame(width: 130)
            }

            if filteredEvents.isEmpty {
                emptyState
            } else {
                LazyVStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(
                        groupedEvents.keys.sorted(by: >),
                        id: \.self
                    ) { date in

                        Text(
                            date.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                        .font(.system(
                            size: 11,
                            weight: .semibold
                        ))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)

                        ForEach(
                            groupedEvents[date] ?? []
                        ) { event in
                            eventRow(event)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func eventRow(
        _ event: ActivityEvent
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: event.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(
                    eventColor(event.type)
                )
                .frame(width: 32, height: 32)
                .background(
                    eventColor(event.type)
                        .opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 6
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(event.type.title)
                    .font(.system(
                        size: 12,
                        weight: .medium
                    ))

                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Text(
                event.timestamp.formatted(
                    date: .omitted,
                    time: .standard
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private func eventColor(
        _ type: ActivityType
    ) -> Color {
        switch type {
        case .sessionStarted,
             .sessionResumed,
             .downloadCompleted:
            return .green

        case .sessionPaused,
             .externalAssertionStarted:
            return .orange

        case .systemSleep:
            return .purple

        case .systemWake,
             .downloadStarted:
            return .blue

        case .downloadFailed:
            return .red

        default:
            return .secondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No activity found")
                .font(.system(
                    size: 13,
                    weight: .medium
                ))

            Text(
                "Recorded activity will appear here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = manager.error {
                Label(
                    error,
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            HStack {
                Text("Keep history for")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "",
                    selection: $manager.retentionDays
                ) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
                .frame(width: 110)

                Spacer()

                Button("Clear History") {
                    showClearConfirmation = true
                }
                .foregroundStyle(.red)
            }
        }
    }
}