import Foundation
import SwiftData

/// First-run content for the watch.
///
/// iOS cannot hand the watch another app's notifications, so without this the feed
/// would open empty on a fresh install and there would be nothing to demonstrate the
/// summarise flow. Seeding happens once, guarded by an empty store.
enum WatchSampleData {
    private static let samples: [Sample] = [
        Sample(
            original: "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction.",
            summary: "$42.50 charge at Starbucks on card ending in 4092.",
            category: .finance,
            age: -180
        ),
        Sample(
            original: "Team stand-up moved to 10:30 AM. Please review the sprint board before joining.",
            summary: "Review the sprint board before the 10:30 AM stand-up.",
            category: .work,
            age: -3600
        ),
        Sample(
            original: "New sign-in detected on your account. If this wasn't you, secure your account now.",
            summary: "Review the new sign-in and secure your account if it wasn't you.",
            category: .security,
            age: -7200
        ),
        Sample(
            original: "Sofia commented on your photo: 'This is the one!' and 4 others liked it.",
            summary: "Sofia commented on your photo.",
            category: .social,
            age: -14400
        ),
        Sample(
            original: "Weekend sale: 40% off all running shoes until Sunday night.",
            summary: "40% off running shoes this weekend.",
            category: .promotional,
            age: -28800
        ),
    ]

    /// Inserts the sample notifications when the store is empty.
    ///
    /// - Parameter context: Main context to insert into.
    /// - Returns: `true` when samples were written, `false` if the store already had rows.
    @discardableResult
    static func seedIfNeeded(into context: ModelContext) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<SummarizedNotification>())) ?? []
        guard existing.isEmpty else { return false }

        for sample in samples {
            context.insert(
                SummarizedNotification(
                    originalText: sample.original,
                    summary: sample.summary,
                    category: sample.category,
                    timestamp: .now.addingTimeInterval(sample.age)
                )
            )
        }
        try? context.save()
        return true
    }

    /// The texts the capture screen offers as starting points.
    ///
    /// Dictation on the watch is slow for long strings, so one-tap templates make the
    /// "try it now" path a single tap instead of a typing session.
    static let captureTemplates: [String] = [
        "Your card ending in 4092 was charged $18.99 at Whole Foods. Tap to view transaction.",
        "Stand-up moved to 9:45 AM. Please review the sprint board before joining.",
        "New sign-in from a new device. If this wasn't you, secure your account now.",
        "Weekend sale: 30% off all outerwear. Limited time only.",
    ]
}

private struct Sample {
    let original: String
    let summary: String
    let category: NotificationCategory
    /// Negative offsets from now, so the feed reads "3m ago", "1h ago", ...
    let age: TimeInterval
}
