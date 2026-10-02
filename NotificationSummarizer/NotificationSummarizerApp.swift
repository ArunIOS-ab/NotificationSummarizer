import SwiftData
import SwiftUI

@main
struct NotificationSummarizerApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([SummarizedNotification.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create local SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NotificationDashboardView()
        }
        .modelContainer(modelContainer)
    }
}
