import SwiftData
import SwiftUI

struct NotificationDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SummarizedNotification.timestamp, order: .reverse) private var notifications: [SummarizedNotification]
    @State private var selectedCategory: NotificationCategory?
    @State private var isRunning = false
    @State private var testText = "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction."
    @State private var testResult: String?

    private var filtered: [SummarizedNotification] {
        guard let selectedCategory else { return notifications }
        return notifications.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CategoryChipRow(selection: $selectedCategory)
                    LocalAITestCard(
                        text: testText,
                        isRunning: isRunning,
                        result: testResult,
                        onRun: runLocalSummary
                    )
                    LazyVStack(spacing: 14) {
                        ForEach(filtered) { notification in
                            NotificationCardView(notification: notification)
                                .onTapGesture {
                                    notification.isRead = true
                                    try? modelContext.save()
                                }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Notifications")
            .background(Color(uiColor: .systemGroupedBackground))
            .task { seedDemoDataIfNeeded() }
        }
    }

    private func runLocalSummary() {
        Task {
            isRunning = true
            defer { isRunning = false }
            let engine = LocalMLEngineActor.shared
            let category = await engine.classify(text: testText)
            let summary = (try? await engine.summarize(text: testText)) ?? "Unable to summarize."
            testResult = "\(category.rawValue) • \(summary)"
        }
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

#Preview {
    let container = try! ModelContainer(for: SummarizedNotification.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(SummarizedNotification(
        originalText: "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction.",
        summary: "$42.50 charge at Starbucks on card ending in 4092.",
        category: .finance,
        timestamp: .now.addingTimeInterval(-180)
    ))
    context.insert(SummarizedNotification(
        originalText: "Team stand-up moved to 10:30 AM. Please review the sprint board before joining.",
        summary: "Review the sprint board before the 10:30 AM stand-up.",
        category: .work,
        timestamp: .now.addingTimeInterval(-3600)
    ))
    context.insert(SummarizedNotification(
        originalText: "New sign-in detected on your account. If this wasn't you, secure your account now.",
        summary: "Review the new sign-in and secure your account if it wasn't you.",
        category: .security,
        timestamp: .now.addingTimeInterval(-7200)
    ))
    return NotificationDashboardView().modelContainer(container)
}
