import SwiftData
import SwiftUI

/// Totals, per-category breakdown and bulk actions.
///
/// The watch equivalent of the phone's stats header plus sidebar filter, compressed
/// into one scrollable page: counts first, then the destructive actions, because those
/// are the only two things this screen is for.
struct WatchOverviewView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SummarizedNotification.timestamp, order: .reverse) private var notifications: [SummarizedNotification]

    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent {
                        Text(stats.total.formatted())
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    } label: {
                        Label("Summarised", systemImage: "bell.fill")
                    }

                    LabeledContent {
                        Text(stats.unread.formatted())
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    } label: {
                        Label("Unread", systemImage: "circlebadge.fill")
                    }
                }

                Section("Categories") {
                    ForEach(NotificationCategory.allCases) { category in
                        LabeledContent {
                            Text(stats.count(for: category).formatted())
                                .monospacedDigit()
                        } label: {
                            Label {
                                Text(category.rawValue)
                            } icon: {
                                Image(systemName: category.systemImage)
                                    .foregroundStyle(category.tint)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        markAllRead()
                    } label: {
                        Label("Mark all read", systemImage: "checkmark.circle")
                    }
                    .disabled(stats.unread == 0)

                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Label("Delete all", systemImage: "trash")
                    }
                    .disabled(stats.total == 0)
                } footer: {
                    Text("Classification and summarisation run on this Apple Watch. Nothing is sent to a server.")
                }
            }
            .navigationTitle("Overview")
            .confirmationDialog("Delete all notifications?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Data

    private var stats: WatchNotificationStats {
        WatchNotificationStats.make(from: notifications)
    }

    // MARK: - Actions

    private func markAllRead() {
        for notification in notifications where !notification.isRead {
            notification.isRead = true
        }
        try? modelContext.save()
    }

    private func deleteAll() {
        for notification in notifications {
            modelContext.delete(notification)
        }
        try? modelContext.save()
    }
}
