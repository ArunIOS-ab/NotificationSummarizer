import SwiftData
import SwiftUI

/// Entry point of the watchOS app.
///
/// The watch reuses `SummarizedNotification` -- the same `@Model` type the iOS app
/// compiles -- so a notification summarised here has an identical shape to one
/// summarised on the phone. It is a *separate* container though: each bundle gets its
/// own SQLite file, and the two stores are never shared at runtime until a
/// WatchConnectivity service is added. See `docs/watchos.md`.
@main
struct NotificationSummarizerWatchApp: App {
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
            WatchRootView()
        }
        .modelContainer(modelContainer)
    }
}
