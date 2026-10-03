import SwiftData
import SwiftUI

/// Root of the app.
///
/// The layout is resolved once, in `AdaptiveLayoutHost`, from the **measured**
/// width of this view. Everything below reads the published
/// `resolvedLayout`, so the sidebar, the card grid and the detail column can never
/// disagree about how many columns fit.
///
/// - `compact`  (< 600pt) — iPhone portrait, Slide Over, narrow Split View:
///   one column, scrolling filter chips, details pushed.
/// - `medium`   (600–899pt) — iPhone landscape, iPad Split View:
///   multi-column grid with the engine panel docked beside it.
/// - `expanded` (>= 900pt) — full width iPad, Stage Manager:
///   sidebar filters, content grid and a persistent detail column.
struct NotificationDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SummarizedNotification.timestamp, order: .reverse) private var notifications: [SummarizedNotification]

    @State private var selectedCategory: NotificationCategory?
    @State private var selectedNotificationID: SummarizedNotification.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var engineText = "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction."
    @State private var isRunning = false
    @State private var engineResult: String?

    var body: some View {
        AdaptiveLayoutHost { layout in
            content(for: layout)
        }
        .task { seedDemoDataIfNeeded() }
    }

    // MARK: - Structure

    @ViewBuilder
    private func content(for layout: ResolvedLayout) -> some View {
        if layout.metrics.showsCategorySidebar {
            splitLayout(layout)
        } else {
            stackLayout(layout)
        }
    }

    // MARK: - Expanded

    private func splitLayout(_ layout: ResolvedLayout) -> some View {
        // Column widths are declared per column rather than on the split view:
        // the modifier binds to no particular column when applied to the split view
        // itself, which previously let the detail column swallow the width and
        // collapse the grid to a single column.
        //
        // The three ideals must sum to less than the narrowest width that can still
        // reach `expanded` (900pt), otherwise there is no layout that fits and the
        // split view resolves by collapsing a column and overflowing the others.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(layout)
                .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 300)
        } content: {
            contentColumn(layout)
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.large)
                .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 560)
        } detail: {
            // Also declared on the detail branch itself, for the same reason.
            Group {
                if let selectedNotification {
                    NotificationDetailView(notification: selectedNotification)
                        .id(selectedNotification.id)
                } else {
                    DetailPlaceholderView(stats: stats)
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 460)
        }
        .navigationSplitViewStyle(.balanced)
        // Three columns are the point of the expanded profile, so keep the sidebar
        // visible rather than letting the system collapse it.
        .onAppear { columnVisibility = .all }
    }

    // MARK: - Compact and medium

    private func stackLayout(_ layout: ResolvedLayout) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: layout.metrics.sectionSpacing) {
                    StatsHeader(stats: stats, metrics: layout.metrics)

                    CategoryFilterRow(
                        selection: $selectedCategory,
                        stats: stats,
                        metrics: layout.metrics
                    )

                    if filtered.isEmpty {
                        EmptyStateView(selectedCategory: selectedCategory)
                    } else {
                        AdaptiveCardGrid {
                            ForEach(filtered) { notification in
                                NotificationCardView(notification: notification)
                            }
                        }
                    }

                    enginePanel(layout)
                        .environment(\.resolvedLayout, layout)
                }
                .padding(layout.metrics.contentPadding)
                .readableContentWidth()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Notifications")
            .navigationDestination(item: $selectedNotificationID) { id in
                if let notification = notifications.first(where: { $0.id == id }) {
                    NotificationDetailView(notification: notification)
                }
            }
        }
    }

    // MARK: - Sidebar

    private func sidebar(_ layout: ResolvedLayout) -> some View {
        List(selection: $selectedCategory) {
            Section("Categories") {
                sidebarFilterRow(title: "All", icon: "square.grid.2x2", count: stats.total, category: nil)
                ForEach(NotificationCategory.allCases) { category in
                    sidebarFilterRow(
                        title: category.rawValue,
                        icon: category.systemImage,
                        count: stats.count(for: category),
                        category: category
                    )
                }
            }

            Section {
                LayoutProfileBadge(profile: layout.profile, width: layout.width)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("On-device engine") {
                VStack(alignment: .leading, spacing: 12) {
                    EnginePanel(text: .constant(engineText), isRunning: isRunning, result: engineResult)
                    EngineRunButton(isRunning: isRunning, canRun: canRun) {
                        runEngine()
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NotificationSummarizer")
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
    }

    private func sidebarFilterRow(title: String, icon: String, count: Int, category: NotificationCategory?) -> some View {
        Button {
            selectedCategory = category
            // Keep the detail column in sync when the new filter excludes the selection.
            if let selectedNotification, selectedNotification.category != category {
                selectedNotificationID = nil
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(category?.tint ?? Color.accentColor)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: LayoutMetrics.resolve(for: .expanded).minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(category as NotificationCategory?)
        .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
    }

    // MARK: - Content column (expanded)

    private func contentColumn(_ layout: ResolvedLayout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.metrics.sectionSpacing) {
                if filtered.isEmpty {
                    EmptyStateView(selectedCategory: selectedCategory)
                } else {
                    AdaptiveCardGrid {
                        ForEach(filtered) { notification in
                            NotificationCardView(
                                notification: notification,
                                isSelected: notification.id == selectedNotificationID
                            )
                            .onTapGesture {
                                withAnimation(.snappy) { selectedNotificationID = notification.id }
                            }
                        }
                    }
                }
            }
            .padding(layout.metrics.contentPadding)
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Engine

    @ViewBuilder
    private func enginePanel(_ layout: ResolvedLayout) -> some View {
        if layout.metrics.stacksEnginePanelAboveList {
            VStack(spacing: 12) {
                EnginePanel(text: $engineText, isRunning: isRunning, result: engineResult)
                EngineRunButton(isRunning: isRunning, canRun: canRun) { runEngine() }
            }
        } else {
            // Wide but short: dock the panel beside the content so neither column is
            // squeezed. Sized as a share of the measured width rather than a fixed
            // 300pt, which overflowed narrow Split View windows.
            VStack(spacing: 12) {
                EnginePanel(text: $engineText, isRunning: isRunning, result: engineResult)
                EngineRunButton(isRunning: isRunning, canRun: canRun) { runEngine() }
            }
            .frame(width: max(260, min(340, layout.width * 0.32)))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var canRun: Bool {
        !isRunning && !engineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runEngine() {
        guard canRun else { return }

        Task {
            isRunning = true
            defer { isRunning = false }

            let engine = LocalMLEngineActor.shared
            let category = await engine.classify(text: engineText)
            let summary = await (try? engine.summarize(text: engineText)) ?? "Unable to summarize."
            engineResult = "\(category.rawValue) • \(summary)"
        }
    }

    // MARK: - Data

    private var filtered: [SummarizedNotification] {
        guard let selectedCategory else { return notifications }
        return notifications.filter { $0.category == selectedCategory }
    }

    private var stats: NotificationStats {
        NotificationStats.make(from: notifications)
    }

    private var selectedNotification: SummarizedNotification? {
        guard let selectedNotificationID else { return nil }
        return notifications.first { $0.id == selectedNotificationID }
    }

    private func seedDemoDataIfNeeded() {
        guard notifications.isEmpty else { return }

        let samples: [(String, String, NotificationCategory, TimeInterval)] = [
            (
                "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction.",
                "$42.50 charge at Starbucks on card ending in 4092.",
                .finance,
                -180
            ),
            (
                "Team stand-up moved to 10:30 AM. Please review the sprint board before joining.",
                "Review the sprint board before the 10:30 AM stand-up.",
                .work,
                -3600
            ),
            (
                "New sign-in detected on your account. If this wasn't you, secure your account now.",
                "Review the new sign-in and secure your account if it wasn't you.",
                .security,
                -7200
            ),
        ]

        for sample in samples {
            modelContext.insert(
                SummarizedNotification(
                    originalText: sample.0,
                    summary: sample.1,
                    category: sample.2,
                    timestamp: .now.addingTimeInterval(sample.3)
                )
            )
        }

        try? modelContext.save()
    }
}

/// Surfaces the live layout decision in the sidebar.
///
/// Useful while designing: it makes the measured width and the profile it resolved
/// to visible at runtime instead of only in the Xcode preview device selector.
struct LayoutProfileBadge: View {
    let profile: LayoutProfile
    let width: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.systemImage)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(Int(width.rounded()))pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Layout \(profile.title), \(Int(width.rounded())) points wide")
    }
}

// MARK: - Previews

@MainActor
private func previewContainer(_ count: Int = 3) -> ModelContainer {
    let container = try! ModelContainer(
        for: SummarizedNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let samples: [(String, String, NotificationCategory)] = [
        (
            "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction.",
            "$42.50 charge at Starbucks on card ending in 4092.",
            .finance
        ),
        (
            "Team stand-up moved to 10:30 AM. Please review the sprint board before joining.",
            "Review the sprint board before the 10:30 AM stand-up.",
            .work
        ),
        (
            "New sign-in detected on your account. If this wasn't you, secure your account now.",
            "Review the new sign-in and secure your account if it wasn't you.",
            .security
        ),
    ]

    for (index, sample) in samples.prefix(count).enumerated() {
        container.mainContext.insert(
            SummarizedNotification(
                originalText: sample.0,
                summary: sample.1,
                category: sample.2,
                timestamp: .now.addingTimeInterval(TimeInterval(-180 * (index + 1)))
            )
        )
    }

    return container
}

#Preview("Compact — 390pt") {
    NotificationDashboardView().modelContainer(previewContainer())
        .frame(width: 390, height: 844)
}

#Preview("Medium — 700pt") {
    NotificationDashboardView().modelContainer(previewContainer())
        .frame(width: 700, height: 500)
}

#Preview("Expanded — 1024pt") {
    NotificationDashboardView().modelContainer(previewContainer())
        .frame(width: 1024, height: 768)
}
