@testable import NotificationSummarizer
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest

/// Fixed "now" for every snapshot in this file.
///
/// Timestamps are rendered relative to this instant (see `EnvironmentValues.currentDate`),
/// so pinning it keeps reference images stable no matter when the suite runs.
private let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)

/// Fixed locale for every snapshot in this file.
///
/// `RelativeDateTimeFormatter` renders the same instant differently per locale
/// (`en_US` = "3m ago", `en_GB`/`en_IN` = "3 min ago"), so the device locale has to
/// be pinned too. Without this, baselines recorded on one machine fail on any
/// runner configured for a different region.
private let referenceLocale = Locale(identifier: "en_US")

/// Records reference images on first run instead of failing, so a fresh clone can
/// generate its baseline in one go. CI flips this to `.never` via
/// `SNAPSHOT_TESTING_RECORD` so an accidental UI change cannot silently rewrite them.
private let recordMode: SnapshotTestingConfiguration.Record = if ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "never" {
    .never
} else {
    .missing
}

// MARK: - Widths under test

/// Widths chosen to sit either side of each breakpoint in `LayoutProfile`.
///
/// The layout is resolved from the measured width, so a plain `.frame(width:)`
/// is enough to select a profile: the snapshots do not depend on which simulator
/// runs them, only on the width being asserted.
private enum Width {
    /// iPhone 15/16/17 portrait.
    static let compact = 393.0
    /// Narrow iPad Split View / 1/3 of a 13" iPad, below `mediumThreshold`.
    static let compactSplit = 507.0
    /// iPad mini portrait and 2/3 of a 13" iPad: `medium`.
    static let medium = 700.0
    /// iPad 11" full screen.
    static let mediumPad = 834.0
    /// Just past `expandedThreshold`.
    static let expanded = 1024.0
    /// 13" iPad in full screen.
    static let wide = 1366.0
}

// MARK: - Fixtures

/// `ModelContainer.mainContext` is `@MainActor`-isolated, so the whole helper
/// (and its callers) have to run on the main actor.
@MainActor
private func makeContainer(_ items: [SummarizedNotification]) throws -> ModelContainer {
    let container = try ModelContainer(
        for: SummarizedNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    for item in items {
        container.mainContext.insert(item)
    }
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
        age: 3600
    )
}

private var securityFixture: SummarizedNotification {
    notification(
        text: "New sign-in detected on your account. If this wasn't you, secure your account now.",
        summary: "Review the new sign-in and secure your account if it wasn't you.",
        category: .security,
        age: 7200,
        isRead: true
    )
}

/// Shared view modifiers so every harness is deterministic regardless of host.
private extension View {
    /// Pins the clock and locale, and forces a profile derived from `width`.
    ///
    /// The resolved layout is injected explicitly rather than measured, so the
    /// assertions do not depend on the simulator's real size class.
    func snapshotFixed(width: CGFloat, dynamicTypeSize: DynamicTypeSize = .large) -> some View {
        let layout = ResolvedLayout.resolve(
            width: width,
            horizontalSizeClass: width >= LayoutProfile.expandedThreshold ? .regular : .compact,
            verticalSizeClass: .regular,
            idiom: width >= LayoutProfile.expandedThreshold ? .pad : .phone,
            dynamicTypeSize: dynamicTypeSize
        )

        return resolvedLayout(layout)
            // Must match the size the metrics were resolved for. Resolving tokens
            // for accessibility3 while rendering the text at the default size makes
            // the snapshot depend on which of the two wins, so it is not stable.
            .dynamicTypeSize(dynamicTypeSize)
            .environment(\.currentDate, referenceNow)
            .environment(\.currentLocale, referenceLocale)
    }
}

// MARK: - Engine panel states

/// Covers the states of the on-device engine panel.
///
/// State is supplied rather than owned so idle, running, success and error are all
/// reachable without waiting on a real Core ML inference.
final class EnginePanelSnapshotTests: XCTestCase {
    private func assertPanel(
        text: String,
        isRunning: Bool,
        result: String?,
        named name: String,
        width: CGFloat = Width.compact,
        colorScheme: ColorScheme = .light
    ) {
        let metrics = LayoutMetrics.resolve(for: LayoutProfile.resolve(width: width))

        let view = EnginePanel(text: .constant(text), isRunning: isRunning, result: result)
            .frame(width: width)
            .snapshotFixed(width: width)
            .preferredColorScheme(colorScheme)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
        XCTAssertGreaterThan(metrics.minimumTapTarget, 0)
    }

    /// Idle: no run yet, so no result banner.
    func testIdleState() {
        assertPanel(text: "Charged $42.50 at Starbucks.", isRunning: false, result: nil, named: "idle")
    }

    /// The button is disabled while a run is in flight.
    func testRunningState() {
        assertPanel(text: "Charged $42.50 at Starbucks.", isRunning: true, result: nil, named: "loading")
    }

    func testSuccessState() {
        assertPanel(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: "Finance • $42.50 charge at Starbucks.",
            named: "success"
        )
    }

    func testErrorState() {
        assertPanel(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: "Unable to summarize.",
            named: "error"
        )
    }

    /// A long result has to wrap rather than truncate.
    func testLongResultState() {
        assertPanel(
            text: "Team stand-up moved.",
            isRunning: false,
            result: "Work • The team stand-up moved to 10:30 AM, please review the sprint board and the retrospective notes before joining.",
            named: "long-result"
        )
    }

    func testEmptyInputState() {
        assertPanel(text: "", isRunning: false, result: nil, named: "empty-input")
    }

    /// Whitespace is treated as empty, so the run button stays disabled.
    func testWhitespaceInputState() {
        assertPanel(text: "   \n\t  ", isRunning: false, result: nil, named: "whitespace-input")
    }

    /// The panel widens and loses the "On device" badge as the container grows.
    func testWideLayout() {
        assertPanel(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: "Finance • $42.50 charge.",
            named: "wide",
            width: Width.expanded
        )
    }

    func testDarkMode() {
        assertPanel(
            text: "Charged $42.50 at Starbucks.",
            isRunning: false,
            result: "Finance • $42.50 charge.",
            named: "idle-dark",
            colorScheme: .dark
        )
    }
}

// MARK: - Notification card states

final class NotificationCardSnapshotTests: XCTestCase {
    private func assertCard(
        _ item: SummarizedNotification,
        named name: String,
        width: CGFloat = Width.compact,
        colorScheme: ColorScheme = .light,
        isSelected: Bool = false
    ) {
        let view = NotificationCardView(notification: item, isSelected: isSelected)
            .frame(width: width - 32)
            .snapshotFixed(width: width)
            .preferredColorScheme(colorScheme)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    func testUnreadNotification() {
        assertCard(financeFixture, named: "unread")
    }

    func testReadNotification() {
        assertCard(securityFixture, named: "read")
    }

    func testSelectedNotification() {
        assertCard(financeFixture, named: "selected", isSelected: true)
    }

    func testDarkMode() {
        assertCard(financeFixture, named: "unread-dark", colorScheme: .dark)
    }

    func testLongSummary() {
        assertCard(
            notification(
                text: "Team stand-up moved to 10:30 AM. Please review the sprint board before joining.",
                summary: "The team stand-up moved to 10:30 AM, please review the sprint board, the retrospective notes and the release checklist before joining.",
                category: .work,
                age: 3600
            ),
            named: "long-summary"
        )
    }

    func testVeryLongOriginalText() {
        assertCard(
            notification(
                text: "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction. This is a deliberately long body used to verify the card clamps the original text to three lines while leaving the summary fully visible.",
                summary: "$42.50 charge.",
                category: .finance,
                age: 60
            ),
            named: "long-content"
        )
    }

    /// A short summary must not stretch the card to match a long body.
    func testShortSummaryLongBody() {
        assertCard(
            notification(
                text: "Charged $42.50 at Starbucks. Tap to view transaction.",
                summary: "$42.50.",
                category: .finance,
                age: 120
            ),
            named: "short-summary"
        )
    }

    /// Category badge tints carry meaning without relying on the label.
    func testEveryCategoryBadge() {
        for category in NotificationCategory.allCases {
            assertCard(
                notification(
                    text: "Sample notification for \(category.rawValue).",
                    summary: "A \(category.rawValue.lowercased()) update.",
                    category: category,
                    age: 300
                ),
                named: "badge-\(category.rawValue.lowercased())"
            )
        }
    }

    /// Wider cards get the expanded profile's larger summary type.
    func testExpandedProfileCard() {
        assertCard(financeFixture, named: "expanded-profile", width: Width.expanded)
    }

    func testOldTimestamp() {
        assertCard(
            notification(
                text: "Old item.",
                summary: "Old update.",
                category: .personal,
                age: 60 * 60 * 24 * 9
            ),
            named: "old-timestamp"
        )
    }
}

// MARK: - Category filters

final class CategoryFilterSnapshotTests: XCTestCase {
    /// Hosts the `@State` the filter row binds to, so the initial selection is
    /// genuinely applied rather than always defaulting to nil.
    private struct FilterHarness: View {
        @State private var selection: NotificationCategory?
        let stats: NotificationStats
        let metrics: LayoutMetrics

        init(selection: NotificationCategory?, metrics: LayoutMetrics, stats: NotificationStats) {
            _selection = State(initialValue: selection)
            self.metrics = metrics
            self.stats = stats
        }

        var body: some View {
            CategoryFilterRow(selection: $selection, stats: stats, metrics: metrics)
        }
    }

    private func assertFilters(
        selection: NotificationCategory?,
        named name: String,
        width: CGFloat = Width.compact
    ) {
        let profile = LayoutProfile.resolve(width: width)
        let metrics = LayoutMetrics.resolve(for: profile)
        // Populate every bucket so the count badges are exercised.
        let stats = NotificationStats(
            total: 6,
            unread: 4,
            countsByCategory: Dictionary(uniqueKeysWithValues: NotificationCategory.allCases.map { ($0, 1) })
        )

        let view = FilterHarness(selection: selection, metrics: metrics, stats: stats)
            .frame(width: width)
            .padding(.vertical, 8)
            .snapshotFixed(width: width)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    func testAllSelected() {
        assertFilters(selection: nil, named: "all-selected")
    }

    func testCategorySelected() {
        assertFilters(selection: .security, named: "category-selected")
    }

    func testWorkSelected() {
        assertFilters(selection: .work, named: "chips-work")
    }

    func testSocialSelected() {
        assertFilters(selection: .social, named: "chips-social")
    }

    func testFinanceSelected() {
        assertFilters(selection: .finance, named: "chips-finance")
    }

    func testSecuritySelected() {
        assertFilters(selection: .security, named: "chips-security")
    }

    func testPromotionalSelected() {
        assertFilters(selection: .promotional, named: "chips-promotional")
    }

    func testPersonalSelected() {
        assertFilters(selection: .personal, named: "chips-personal")
    }

    /// Once there is width for it the row wraps instead of scrolling, so no chip
    /// is ever half off-screen.
    func testWrappingLayoutAtExpandedWidth() {
        assertFilters(selection: nil, named: "wrapping-expanded", width: Width.expanded)
    }
}

// MARK: - Stats header

final class StatsHeaderSnapshotTests: XCTestCase {
    private func assertHeader(_ stats: NotificationStats, named name: String, width: CGFloat) {
        let metrics = LayoutMetrics.resolve(for: LayoutProfile.resolve(width: width))

        let view = StatsHeader(stats: stats, metrics: metrics)
            .frame(width: width - 32)
            .snapshotFixed(width: width)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    func testPopulated() {
        assertHeader(
            NotificationStats(
                total: 12,
                unread: 5,
                countsByCategory: [.finance: 6, .work: 4, .security: 2]
            ),
            named: "populated",
            width: Width.compact
        )
    }

    func testEmpty() {
        assertHeader(NotificationStats(total: 0, unread: 0, countsByCategory: [:]), named: "empty", width: Width.compact)
    }

    func testAllRead() {
        assertHeader(
            NotificationStats(
                total: 8,
                unread: 0,
                countsByCategory: [.work: 8]
            ),
            named: "all-read",
            width: Width.compact
        )
    }

    /// A single-digit count must not shift the tiles out of alignment.
    func testSingleDigitCounts() {
        assertHeader(
            NotificationStats(total: 1, unread: 1, countsByCategory: [.social: 1]),
            named: "single-item",
            width: Width.compact
        )
    }
}

// MARK: - Layout profile badge

final class LayoutProfileBadgeSnapshotTests: XCTestCase {
    private func assertBadge(profile: LayoutProfile, width: CGFloat, named name: String) {
        let view = LayoutProfileBadge(profile: profile, width: width)
            .frame(width: 220)
            .snapshotFixed(width: width)
        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    func testCompactBadge() {
        assertBadge(profile: .compact, width: Width.compact, named: "compact")
    }

    func testMediumBadge() {
        assertBadge(profile: .medium, width: Width.medium, named: "medium")
    }

    func testExpandedBadge() {
        assertBadge(profile: .expanded, width: Width.expanded, named: "expanded")
    }
}

// MARK: - Full dashboard across breakpoints

/// Renders the dashboard at each breakpoint.
///
/// This is the end-to-end guard: it proves the measured width selects the right
/// structure, and that the sidebar, grid and detail column agree on how many
/// columns fit.
///
/// `@MainActor` because `makeContainer` touches `ModelContainer.mainContext`.
@MainActor
final class NotificationDashboardSnapshotTests: XCTestCase {
    private func assertDashboard(
        items: [SummarizedNotification],
        width: CGFloat,
        height: CGFloat,
        named name: String,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize? = nil
    ) throws {
        let container = try makeContainer(items)

        let view = NotificationDashboardView()
            .modelContainer(container)
            .snapshotFixed(width: width, dynamicTypeSize: dynamicTypeSize ?? .large)
            .preferredColorScheme(colorScheme)
            .frame(width: width, height: height)

        assertSnapshot(of: view, as: .image, named: name, record: recordMode)
    }

    /// iPhone portrait: one column, stacked sections.
    func testCompactDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture, securityFixture],
            width: Width.compact,
            height: 844,
            named: "compact"
        )
    }

    /// The regression case: 507pt reports a compact size class but is a tablet
    /// window, and must not try to show two columns it cannot fit.
    func testNarrowSplitViewDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture],
            width: Width.compactSplit,
            height: 800,
            named: "compact-split"
        )
    }

    /// 2/3 of a 13" iPad: wide enough for two columns, too narrow for a sidebar.
    func testMediumDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture, securityFixture],
            width: Width.medium,
            height: 900,
            named: "medium"
        )
    }

    /// iPad 11" full screen is still below the expanded threshold.
    func testMediumPadDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture],
            width: Width.mediumPad,
            height: 1000,
            named: "medium-pad"
        )
    }

    /// Past the threshold: sidebar, content grid and detail column.
    func testExpandedDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture, securityFixture],
            width: Width.expanded,
            height: 768,
            named: "expanded"
        )
    }

    /// 13" full screen: the widest layout the project supports.
    func testWideDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture, securityFixture],
            width: Width.wide,
            height: 1024,
            named: "wide"
        )
    }

    func testEmptyDashboard() throws {
        try assertDashboard(items: [], width: Width.compact, height: 844, named: "empty")
    }

    func testSingleItemDashboard() throws {
        try assertDashboard(items: [financeFixture], width: Width.compact, height: 844, named: "single-item")
    }

    func testAllReadDashboard() throws {
        try assertDashboard(
            items: [
                notification(
                    text: "Read one.",
                    summary: "Already seen.",
                    category: .finance,
                    age: 180,
                    isRead: true
                ),
                notification(
                    text: "Read two.",
                    summary: "Also seen.",
                    category: .work,
                    age: 3600,
                    isRead: true
                ),
            ],
            width: Width.compact,
            height: 844,
            named: "all-read"
        )
    }

    /// Long bodies are the main reason a card grid can grow without bound.
    func testPopulatedLongContentDashboard() throws {
        try assertDashboard(
            items: [
                notification(
                    text: "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction for the full itemised breakdown including tax and gratuity.",
                    summary: "$42.50 charge at Starbucks on card ending in 4092.",
                    category: .finance,
                    age: 180
                ),
                notification(
                    text: "Team stand-up moved to 10:30 AM. Please review the sprint board and the retrospective notes before joining the call.",
                    summary: "Review the sprint board before the 10:30 AM stand-up.",
                    category: .work,
                    age: 3600
                ),
            ],
            width: Width.expanded,
            height: 768,
            named: "expanded-long-content"
        )
    }

    func testExpandedDarkMode() throws {
        try assertDashboard(
            items: [financeFixture, workFixture],
            width: Width.expanded,
            height: 768,
            named: "expanded-dark",
            colorScheme: .dark
        )
    }

    /// Accessibility Dynamic Type must not silently clip the filter labels.
    func testAccessibilityTypeDashboard() throws {
        try assertDashboard(
            items: [financeFixture, workFixture],
            width: Width.compact,
            height: 1200,
            named: "accessibility-type",
            dynamicTypeSize: .accessibility3
        )
    }
}
