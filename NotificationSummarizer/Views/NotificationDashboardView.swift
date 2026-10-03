import SwiftData
import SwiftUI

/// Root of the app.
///
/// The dashboard picks one of three structural layouts from the current size
/// class, then hands a resolved `DashboardMetrics` down so every surface shares
/// the same spacing, type scale and corner radii.
///
/// - `compact`  — iPhone portrait: chips + one column of cards, details pushed.
/// - `medium`   — iPhone landscape or a narrow iPad window: two column grid with
///   the AI test panel docked beside it.
/// - `expanded` — iPad full screen: sidebar filters, multi column grid and a
///   persistent detail column.
struct NotificationDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \SummarizedNotification.timestamp, order: .reverse) private var notifications: [SummarizedNotification]

    @State private var selectedCategory: NotificationCategory?
    @State private var selectedNotificationID: SummarizedNotification.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var layout: DashboardLayout {
        DashboardLayout.resolve(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass,
            idiom: .current
        )
    }

    private var metrics: DashboardMetrics {
        DashboardMetrics.resolve(for: layout, dynamicTypeSize: dynamicTypeSize)
    }

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

    var body: some View {
        Group {
            if metrics.showsCategorySidebar {
                splitLayout
            } else {
                stackLayout
            }
        }
        .adaptiveDashboardLayout()
        .task { seedDemoDataIfNeeded() }
    }

    // MARK: - Expanded (iPad)

    private var splitLayout: some View {
        // Column widths are declared per column rather than on the split view:
        // modifiers applied to the split view itself do not reliably bind to the
        // individual columns, which previously let the detail column swallow the
        // width and collapse the grid to one column.
        // The three ideals must sum to less than the narrowest iPad width we support
        // (744pt on iPad mini), otherwise the split view has no layout that fits
        // and resolves by collapsing a column and overflowing the others.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 300)
        } content: {
            contentGrid(
                header: { statsSummary },
                onSelect: { notification in
                    withAnimation(.snappy) { selectedNotificationID = notification.id }
                },
                selectedID: selectedNotificationID
            )
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 560)
        } detail: {
            // Declared here on the detail branch itself. Applying
            // `navigationSplitViewColumnWidth` to the NavigationSplitView binds to
            // no particular column, which is why the detail previously stole the
            // width and pushed the grid down to a single column.
            Group {
                if let selectedNotification {
                    NotificationDetailView(notification: selectedNotification, metrics: metrics)
                        .id(selectedNotification.id)
                } else {
                    DetailPlaceholderView(metrics: metrics, stats: stats)
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 460)
        }
        .navigationSplitViewStyle(.balanced)
        // Three columns are the whole point of the expanded profile, so the
        // sidebar stays visible rather than letting the system collapse it.
        .onAppear { columnVisibility = .all }
        .tint(.accentColor)
    }

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            Section {
                sidebarFilterRow(
                    title: "All",
                    icon: "square.grid.2x2",
                    count: stats.total,
                    category: nil
                )

                ForEach(NotificationCategory.allCases) { category in
                    sidebarFilterRow(
                        title: category.rawValue,
                        icon: category.systemImage,
                        count: stats.count(for: category),
                        category: category
                    )
                }
            } header: {
                Text("Categories")
            }

            Section {
                LayoutProfileBadge(layout: layout, horizontal: horizontalSizeClass, vertical: verticalSizeClass)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                AdaptiveLocalAITestCard(metrics: metrics)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("On-device engine")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NotificationSummarizer")
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
    }

    private func sidebarFilterRow(title: String, icon: String, count: Int, category: NotificationCategory?) -> some View {
        Button {
            selectedCategory = category
            // Keep the detail column in sync when the new filter has no selection.
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
            .frame(minHeight: metrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(category as NotificationCategory?)
        .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
    }

    // MARK: - Compact and medium

    private var stackLayout: some View {
        NavigationStack {
            ScrollView {
                if metrics.stacksTestCardAboveList {
                    compactColumn
                } else {
                    mediumColumn
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Notifications")
            .navigationDestination(item: $selectedNotificationID) { id in
                if let notification = notifications.first(where: { $0.id == id }) {
                    NotificationDetailView(notification: notification, metrics: metrics)
                }
            }
        }
    }

    /// iPhone portrait: everything stacked in one scrollable, readable column.
    private var compactColumn: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            if metrics.showsInlineStatsHeader {
                statsSummary
            }

            CategoryFilterView(selection: $selectedCategory, stats: stats, metrics: metrics)

            if filtered.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: metrics.cardSpacing) {
                    ForEach(filtered) { notification in
                        AdaptiveNotificationCardView(notification: notification, metrics: metrics)
                    }
                }
            }

            AdaptiveLocalAITestCard(metrics: metrics)
        }
        .padding(metrics.contentPadding)
        .readableContentWidth()
    }

    /// iPhone landscape: list on the left, engine panel docked on the right so
    /// neither column is squeezed into an unusable height.
    private var mediumColumn: some View {
        HStack(alignment: .top, spacing: metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                if metrics.showsInlineStatsHeader {
                    statsSummary
                }

                CategoryFilterView(selection: $selectedCategory, stats: stats, metrics: metrics)

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: metrics.gridColumns, alignment: .leading, spacing: metrics.cardSpacing) {
                        ForEach(filtered) { notification in
                            AdaptiveNotificationCardView(notification: notification, metrics: metrics)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AdaptiveLocalAITestCard(metrics: metrics)
                .frame(width: 300)
        }
        .padding(metrics.contentPadding)
    }

    // MARK: - Shared pieces

    private var statsSummary: some View {
        StatsHeaderView(stats: stats, metrics: metrics)
    }

    @ViewBuilder
    private func contentGrid<Header: View>(
        header: @escaping () -> Header,
        onSelect: @escaping (SummarizedNotification) -> Void,
        selectedID: SummarizedNotification.ID?
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                header()

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: metrics.gridColumns, alignment: .leading, spacing: metrics.cardSpacing) {
                        ForEach(filtered) { notification in
                            AdaptiveNotificationCardView(
                                notification: notification,
                                metrics: metrics,
                                isSelected: notification.id == selectedID
                            )
                            .onTapGesture { onSelect(notification) }
                        }
                    }
                }
            }
            .padding(metrics.contentPadding)
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing here", systemImage: "tray")
        } description: {
            Text(selectedCategory.map { "No \($0.rawValue.lowercased()) notifications yet." } ?? "No notifications yet.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.sectionSpacing)
    }

    // MARK: - Demo data

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
            )
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

/// Surfaces the active profile in the iPad sidebar.
///
/// Useful while designing: it makes the size class the layout resolved to
/// visible at runtime instead of only in the Xcode preview device selector.
struct LayoutProfileBadge: View {
    let layout: DashboardLayout
    let horizontal: UserInterfaceSizeClass?
    let vertical: UserInterfaceSizeClass?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: layout.systemImage)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(layout.title)
                    .font(.subheadline.weight(.semibold))
                Text(sizeClassSummary)
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
        .accessibilityLabel("Layout \(layout.title), size class \(sizeClassSummary)")
    }

    private var sizeClassSummary: String {
        "h: \(horizontal.shortTitle) · v: \(vertical.shortTitle)"
    }
}

extension Optional where Wrapped == UserInterfaceSizeClass {
    var shortTitle: String {
        switch self {
        case .some(.compact): "compact"
        case .some(.regular): "regular"
        case .none: "nil"
        @unknown default: "unknown"
        }
    }
}

// MARK: - Previews

// SwiftUI resolves size classes from the traits supplied to the preview
// provider, so these previews exercise the real branch each device selects.
#Preview("iPhone portrait — compact", traits: .fixedLayout(width: 393, height: 852)) {
    previewDashboard
}

#Preview("iPhone landscape — medium", traits: .fixedLayout(width: 852, height: 393)) {
    previewDashboard
}

#Preview("iPad portrait — expanded", traits: .fixedLayout(width: 834, height: 1194)) {
    previewDashboard
}

#Preview("iPad Split View — medium", traits: .fixedLayout(width: 507, height: 1194)) {
    previewDashboard
}

#Preview("iPhone accessibility size", traits: .fixedLayout(width: 393, height: 852)) {
    previewDashboard
        .dynamicTypeSize(.accessibility3)
}

@MainActor
private var previewDashboard: some View {
    let container = try! ModelContainer(
        for: SummarizedNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

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
        )
    ]

    for (index, sample) in samples.enumerated() {
        context.insert(
            SummarizedNotification(
                originalText: sample.0,
                summary: sample.1,
                category: sample.2,
                timestamp: .now.addingTimeInterval(TimeInterval(-180 * (index + 1)))
            )
        )
    }

    return NotificationDashboardView().modelContainer(container)
}