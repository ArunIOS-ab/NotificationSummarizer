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
                    categoryChips
                    testCard
                    LazyVStack(spacing: 14) {
                        ForEach(filtered) { notification in
                            notificationCard(notification)
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

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", icon: "square.grid.2x2", active: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(NotificationCategory.allCases) { category in
                    chip(title: category.rawValue, icon: category.systemImage, active: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private func chip(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(active ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Local AI test", systemImage: "cpu")
                .font(.headline)
            TextEditor(text: $testText)
                .frame(minHeight: 90)
                .padding(8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            Button {
                Task {
                    isRunning = true
                    defer { isRunning = false }
                    let engine = LocalMLEngineActor.shared
                    let category = await engine.classify(text: testText)
                    let summary = (try? await engine.summarize(text: testText)) ?? "Unable to summarize."
                    testResult = "\(category.rawValue) • \(summary)"
                }
            } label: {
                Label(isRunning ? "Running locally…" : "Run Local AI Summary", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let testResult {
                Text(testResult)
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
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

    private func notificationCard(_ notification: SummarizedNotification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(notification.category.rawValue, systemImage: notification.category.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
                Spacer()
                Text(notification.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(notification.originalText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(notification.summary)
                .font(.body.weight(.semibold))
            HStack {
                Circle().fill(notification.isRead ? Color.secondary : Color.green).frame(width: 7, height: 7)
                Text(notification.isRead ? "Read" : "Unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture {
            notification.isRead = true
            try? modelContext.save()
        }
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
