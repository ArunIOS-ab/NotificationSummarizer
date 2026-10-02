import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import NotificationSummarizer

/// Fixed "now" for every snapshot in this file.
///
/// Timestamps are rendered relative to this instant (see `EnvironmentValues.currentDate`),
/// so pinning it keeps reference images stable no matter when the suite runs.
private let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)

/// Records reference images on first run instead of failing, so a fresh clone can
/// generate its baseline in one go. CI flips this to `.never` via
/// `SNAPSHOT_TESTING_RECORD` so an accidental UI change cannot silently rewrite them.
private let recordMode: SnapshotTestingConfiguration.Record = {
    if ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "never" { .never } else { .missing }
}()

// MARK: - Fixtures

/// `ModelContainer.mainContext` is `@MainActor`-isolated, so the whole helper
/// (and its callers) have to run on the main actor.
@MainActor
private func makeContainer(_ items: [SummarizedNotification]) throws -> ModelContainer {
    let container = try ModelContainer(
        for: SummarizedNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    for item in items { container.mainContext.insert(item) }
    return container
}

private func notification(
    text: String,
    summary: String,
    category: NotificationCategory,
    age: TimeInterval,
    isRead: Bool = false
) -> SummarizedNotification {
    SummarizedNotification(
        originalText: text,
        summary: summary,
        category: category,
        timestamp: referenceNow.addingTimeInterval(-age),
        isRead: isRead
    )
}

private var financeFixture: SummarizedNotification {
    notification(
        text: "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction.",
        summary: "$42.50 charge at Starbucks on card ending in 4092.",
        category: .finance,
        age: 180
    )
}

private var workFixture: SummarizedNotification {
    notification(
        text: "Team stand-up moved to 10:30 AM. Please review the sprint board before joining.",
        summary: "Review the sprint board before the 10:30 AM stand-up.",
        category: .work,
        age: 3_600
    )
}

private var securityFixture: SummarizedNotification {
    notification(
        text: "New sign-in detected on your account. If this wasn't you, secure your account now.",
        summary: "Review the new sign-in and secure your account if it wasn't you.",
        category: .security,
        age: 7_200,
        isRead: true
    )
}

// MARK: - LocalAITestCard states

/// Covers the four reachable states of the "Local AI test" panel.
///
/// `isRunning` / `result` are plain inputs rather than `@State`, so each state can be
/// rendered deterministically without driving a real Core ML inference.
final class LocalAITestCardSnapshotTests: XCTestCase {

    private func assertCard(
        text: String,
        isRunning: Bool,
        result: String?,
        named name: String,
        colorScheme: ColorScheme = .light
    ) {
        let view = LocalAITestCard(text: text, isRunning: isRunning, result: result, onRun: {})
            .frame(width: 390)
            .environment(\.currentDate, referenceNow)
            .preferredColorScheme(colorScheme)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    /// Idle: no run yet, so no result banner.
    func testIdleState() {
        assertCard(text: "Charged $42.50 at Starbucks.", isRunning: false, result: nil, named: "idle")
    }

    /// Loading: the button is disabled and its label switches to "Running locally…".
    func testLoadingState() {
        assertCard(
            text: "Charged $42.50 at Starbucks.",
            isRunning: true,
            result: nil,
            named: "loading"
        )
    }

    /// Success: the result banner renders below the button.
    func testSuccessState() {
        assertCard(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: "Finance • $42.50 charge at Starbucks.",
            named: "success"
        )
    }

    /// Error: summarization fell back, so the banner carries the failure copy.
    func testErrorState() {
        assertCard(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: "Unable to summarize.",
            named: "error"
        )
    }

    /// Empty input: the run button must render disabled because the guard trims whitespace.
    func testEmptyInputDisablesRunButton() {
        assertCard(text: "", isRunning: false, result: nil, named: "empty-input")
    }

    /// Whitespace-only input takes the same disabled path.
    func testWhitespaceOnlyInputDisablesRunButton() {
        assertCard(text: "   \n\t  ", isRunning: false, result: nil, named: "whitespace-input")
    }

    /// A long result exercises the banner's multi-line layout and text truncation.
    func testLongResultWrapsWithoutOverflowing() {
        let long = String(repeating: "Work • Review the sprint board before the 10:30 AM stand-up. ", count: 3)
        assertCard(text: "Team stand-up moved.", isRunning: false, result: long, named: "long-result")
    }

    /// Dark mode is a distinct rendering path and needs its own reference image.
    func testIdleStateDarkMode() {
        assertCard(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: nil,
            named: "idle-dark",
            colorScheme: .dark
        )
    }
}

// MARK: - NotificationCardView states

final class NotificationCardViewSnapshotTests: XCTestCase {

    private func assertCard(_ item: SummarizedNotification, named name: String, colorScheme: ColorScheme = .light) {
        let view = NotificationCardView(notification: item)
            .frame(width: 358)
            .environment(\.currentDate, referenceNow)
            .preferredColorScheme(colorScheme)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    func testUnreadNotification() {
        assertCard(financeFixture, named: "unread")
    }

    func testReadNotificationSwitchesIndicatorAndLabel() {
        assertCard(securityFixture, named: "read")
    }

    /// Missing-data edge case: a record whose original text failed to summarize away.
    func testEmptySummary() {
        assertCard(
            notification(text: "Some notification with no summary", summary: "", category: .personal, age: 600),
            named: "empty-summary"
        )
    }

    func testEmptyOriginalText() {
        assertCard(
            notification(text: "", summary: "A summary survived but the original is gone.", category: .social, age: 600),
            named: "empty-original-text"
        )
    }

    /// Long text on every category-relevant line checks wrapping and truncation.
    func testLongTextWrapsWithinCard() {
        assertCard(
            notification(
                text: String(repeating: "Your bank account was charged at a merchant with a very long name. ", count: 4),
                summary: String(repeating: "Charge at a merchant with a very long name. ", count: 3),
                category: .finance,
                age: 120
            ),
            named: "long-text"
        )
    }

    /// A timestamp far enough back that the relative formatter must pick a coarser unit.
    func testOldTimestampUsesCoarseRelativeUnit() {
        assertCard(
            notification(text: "Old notification", summary: "Old summary", category: .promotional, age: 60 * 60 * 30),
            named: "old-timestamp"
        )
    }

    func testUnreadDarkMode() {
        assertCard(financeFixture, named: "unread-dark", colorScheme: .dark)
    }
}

// MARK: - Category chips

final class CategoryChipRowSnapshotTests: XCTestCase {

    /// Minimal host that owns the `@State` the chip row binds to, so the
    /// initial selection is genuinely applied (rather than always defaulting to nil).
    private struct ChipHarness: View {
        @State private var selection: NotificationCategory?

        init(initial: NotificationCategory?) {
            _selection = State(initialValue: initial)
        }

        var body: some View {
            CategoryChipRow(selection: $selection)
                .frame(width: 390)
                .environment(\.currentDate, referenceNow)
        }
    }

    private func assertChips(selection: NotificationCategory?, named name: String) {
        assertSnapshot(
            of: ChipHarness(initial: selection),
            as: .image,
            named: name,
            record: recordMode
        )
    }

    /// Default state: "All" is active.
    func testAllSelected() {
        assertChips(selection: nil, named: "all-selected")
    }

    /// A category is active, so "All" falls back to the inactive capsule style.
    func testCategorySelected() {
        assertChips(selection: .security, named: "category-selected")
    }

    /// Each category renders its own SF Symbol in the chip.
    func testEveryCategoryRendersItsIcon() {
        for category in NotificationCategory.allCases {
            assertChips(selection: category, named: "chips-\(category.rawValue.lowercased())")
        }
    }
}

// MARK: - Full dashboard

/// End-to-end rendering of the dashboard against a real in-memory SwiftData store.
///
/// Composes the same components the app ships, so a regression in layout, seeding,
/// or the filter interaction surfaces here rather than only in unit tests.
@MainActor
final class NotificationDashboardViewSnapshotTests: XCTestCase {

    @MainActor
    private func assertDashboard(
        items: [SummarizedNotification],
        named name: String,
        colorScheme: ColorScheme = .light
    ) throws {
        let container = try makeContainer(items)

        let view = NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CategoryChipRow(selection: .constant(nil))
                    LocalAITestCard(
                        text: "Your bank account ending in 4092 was charged $42.50 at Starbucks.",
                        isRunning: false,
                        result: nil,
                        onRun: {}
                    )
                    LazyVStack(spacing: 14) {
                        ForEach(items) { NotificationCardView(notification: $0) }
                    }
                }
                .padding()
            }
            .navigationTitle("Notifications")
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .modelContainer(container)
        .environment(\.currentDate, referenceNow)
        .preferredColorScheme(colorScheme)
        .frame(width: 390, height: 700)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    /// Populated list, the state a user sees on a normal launch.
    func testPopulatedDashboard() throws {
        try assertDashboard(items: [financeFixture, workFixture, securityFixture], named: "populated")
    }

    /// Empty state: the store has no records yet.
    func testEmptyDashboard() throws {
        try assertDashboard(items: [], named: "empty")
    }

    /// A single record, guarding against spacing regressions when the list is sparse.
    func testSingleItemDashboard() throws {
        try assertDashboard(items: [financeFixture], named: "single-item")
    }

    /// All items read, so every status dot renders in the "read" colour.
    func testAllItemsReadDashboard() throws {
        try assertDashboard(
            items: [
                notification(text: "A", summary: "A summary", category: .social, age: 60, isRead: true),
                notification(text: "B", summary: "B summary", category: .promotional, age: 120, isRead: true),
            ],
            named: "all-read"
        )
    }

    /// Long content end-to-end, where overflow bugs are most likely to surface.
    func testPopulatedDashboardWithLongContent() throws {
        try assertDashboard(
            items: [
                notification(
                    text: String(repeating: "Standup moved, please review the sprint board before joining. ", count: 3),
                    summary: String(repeating: "Review the sprint board. ", count: 4),
                    category: .work,
                    age: 90
                ),
                notification(
                    text: String(repeating: "Susicious sign-in detected on your account. ", count: 3),
                    summary: "Secure your account if this wasn't you.",
                    category: .security,
                    age: 5_400
                ),
            ],
            named: "populated-long-content"
        )
    }

    func testPopulatedDashboardDarkMode() throws {
        try assertDashboard(
            items: [financeFixture, workFixture, securityFixture],
            named: "populated-dark",
            colorScheme: .dark
        )
    }
}
