import AppIntents
import Foundation
import SwiftData

struct SummarizeNotificationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Notifications"
    static let description = IntentDescription("Analyzes pending notifications locally and speaks a concise brief.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try ModelContainer(for: SummarizedNotification.self)
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<SummarizedNotification>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 3
        let records = try context.fetch(descriptor)

        guard !records.isEmpty else {
            return .result(dialog: "You have no unread summarized notifications.")
        }

        let engine = LocalMLEngineActor.shared
        var briefs: [String] = []
        for record in records {
            let category = await engine.classify(text: record.originalText)
            let summary = await (try? engine.summarize(text: record.originalText)) ?? record.summary
            briefs.append("\(category.rawValue): \(summary)")
        }

        let priorityCount = records.count
        let dialog = "You have \(priorityCount) priority update\(priorityCount == 1 ? "" : "s"): " + briefs.joined(separator: " ")
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
