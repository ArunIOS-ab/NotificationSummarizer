import Foundation
import SwiftData

/// Outcome of one on-device summarise run, rendered by the capture screen.
///
/// `elapsedMilliseconds` is watch-specific UI sugar: the phone shows a spinner, the
/// watch has room for one number, and "38 ms" is the whole feedback loop on a surface
/// where the user has already looked away from their wrist by the time it renders.
struct WatchSummaryResult: Identifiable, Equatable {
    let id = UUID()
    let category: NotificationCategory
    let summary: String
    let elapsedMilliseconds: Int
}

/// Watch-side entry point into the shared on-device engine.
///
/// Deliberately thin: classification and summarization still run in
/// `LocalMLEngineActor`, so the watch inherits the neural model, the 1.5-second
/// timeout and the rule-based fallback without duplicating any of that logic.
@MainActor
enum WatchSummarizer {
    /// Classifies and summarises `text` entirely on device.
    ///
    /// Returns `nil` for blank input so the caller can disable the run button instead
    /// of rendering an error for something the user has not typed yet.
    static func summarize(_ text: String) async -> WatchSummaryResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let startedAt = Date()
        let engine = LocalMLEngineActor.shared
        let category = await engine.classify(text: trimmed)
        let summary = await (try? engine.summarize(text: trimmed)) ?? trimmed

        return WatchSummaryResult(
            category: category,
            summary: summary,
            elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    /// Persists a run so it appears in the watch feed.
    ///
    /// Saving is best-effort like the rest of the app's writes: a failure here costs
    /// the user one history entry, and surfacing a thrown error on a glanceable screen
    /// would cost them the whole capture flow.
    @discardableResult
    static func save(_ result: WatchSummaryResult, originalText: String, into context: ModelContext) -> SummarizedNotification {
        let notification = SummarizedNotification(
            originalText: originalText.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: result.summary,
            category: result.category
        )
        context.insert(notification)
        try? context.save()
        return notification
    }
}
