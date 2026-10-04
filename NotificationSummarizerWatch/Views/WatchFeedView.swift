import SwiftData
import SwiftUI

/// The watch feed: every notification summarised on device, newest first.
///
/// Structure is intentionally different from the phone: there is no stats header and
/// no card grid, because on this screen size a notification row that shows its
/// category, summary and age already *is* the whole layout. Filtering moved into a
/// toolbar `Menu` so the list keeps every row of vertical space.
struct WatchFeedView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SummarizedNotification.timestamp, order: .reverse) private var notifications: [SummarizedNotification]

    /// `nil` means "all categories", matching `WatchNotificationStats.count(for:)`.
    @State private var selectedCategory: NotificationCategory?
    @State private var showsFilterDialog = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Feed")
                .navigationDestination(for: SummarizedNotification.ID.self) { id in
                    detail(for: id)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterButton
                    }
                }
        }
        .task { WatchSampleData.seedIfNeeded(into: modelContext) }
        .confirmationDialog("Filter by category", isPresented: $showsFilterDialog, titleVisibility: .visible) {
            // `Menu` does not exist on watchOS, so the filter is a confirmation dialog:
            // it opens over the whole screen and every entry stays a full-width tappable
            // row, which is the one menu-like pattern watchOS actually supports.
            filterButtonRow(title: "All", icon: "square.grid.2x2", category: nil)

            Divider()

            ForEach(NotificationCategory.allCases) { category in
                filterButtonRow(title: category.rawValue, icon: category.systemImage, category: category)
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Structure

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            ContentUnavailableView(
                "Nothing here",
                systemImage: "bell.slash",
                description: Text(emptyMessage)
            )
        } else {
            List {
                ForEach(filtered) { notification in
                    NavigationLink(value: notification.id) {
                        WatchNotificationRow(notification: notification)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(notification)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleRead(notification)
                        } label: {
                            Label(
                                notification.isRead ? "Mark Unread" : "Mark Read",
                                systemImage: notification.isRead ? "circlebadge" : "checkmark.circle"
                            )
                        }
                        .tint(notification.isRead ? .orange : .accentColor)
                    }
                }
            }
        }
    }

    private var filterButton: some View {
        Button {
            showsFilterDialog = true
        } label: {
            Image(systemName: selectedCategory.map(\.systemImage) ?? "line.3.horizontal.decrease.circle")
                .foregroundStyle(selectedCategory?.tint ?? Color.accentColor)
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(selectedCategory?.rawValue ?? "All categories")
    }

    private func filterButtonRow(title: String, icon: String, category: NotificationCategory?) -> some View {
        Button {
            selectedCategory = category
        } label: {
            // Counts are baked into the label: a confirmation-dialog entry is a single
            // line of text, so a trailing count column would not render.
            Label("\(title) \(stats.count(for: category))", systemImage: icon)
        }
    }

    @ViewBuilder
    private func detail(for id: SummarizedNotification.ID) -> some View {
        // Resolve through the live query rather than capturing the object, so the
        // detail view keeps updating after a swipe marks the item read.
        if let notification = notifications.first(where: { $0.id == id }) {
            WatchDetailView(notification: notification)
                .id(notification.id)
        } else {
            ContentUnavailableView("Removed", systemImage: "trash")
        }
    }

    // MARK: - Data

    private var filtered: [SummarizedNotification] {
        guard let selectedCategory else { return notifications }
        return notifications.filter { $0.category == selectedCategory }
    }

    private var stats: WatchNotificationStats {
        WatchNotificationStats.make(from: notifications)
    }

    private var emptyMessage: String {
        if let selectedCategory {
            return "No \(selectedCategory.rawValue.lowercased()) notifications yet. Capture one from the Capture page."
        }
        return "Capture a notification to see it summarised here."
    }

    // MARK: - Actions

    private func delete(_ notification: SummarizedNotification) {
        modelContext.delete(notification)
        try? modelContext.save()
    }

    private func toggleRead(_ notification: SummarizedNotification) {
        notification.isRead.toggle()
        try? modelContext.save()
    }
}
