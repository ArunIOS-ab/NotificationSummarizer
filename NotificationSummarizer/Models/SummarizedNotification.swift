import Foundation
import SwiftData

@Model
final class SummarizedNotification {
    @Attribute(.unique) var id: UUID
    var originalText: String
    var summary: String
    var categoryRaw: String
    var timestamp: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        originalText: String,
        summary: String,
        category: NotificationCategory,
        timestamp: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.originalText = originalText
        self.summary = summary
        self.categoryRaw = category.rawValue
        self.timestamp = timestamp
        self.isRead = isRead
    }

    var category: NotificationCategory {
        get { NotificationCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }
}
