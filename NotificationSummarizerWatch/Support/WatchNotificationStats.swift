import Foundation

/// Unread/total roll-up for the watch overview screen.
///
/// The phone has a wide header for this; the watch gets a compact count plus a
/// per-category breakdown, which is also what the feed's category filter needs so the
/// menu can label every option with its own count instead of a bare name.
struct WatchNotificationStats: Equatable {
    let total: Int
    let unread: Int
    let countsByCategory: [NotificationCategory: Int]

    static func make(from notifications: [SummarizedNotification]) -> WatchNotificationStats {
        var counts: [NotificationCategory: Int] = [:]
        for notification in notifications {
            counts[notification.category, default: 0] += 1
        }

        return WatchNotificationStats(
            total: notifications.count,
            unread: notifications.lazy.filter { !$0.isRead }.count,
            countsByCategory: counts
        )
    }

    /// Pass `nil` for "all categories", which is what the feed's "All" filter means.
    func count(for category: NotificationCategory?) -> Int {
        guard let category else { return total }
        return countsByCategory[category] ?? 0
    }
}
