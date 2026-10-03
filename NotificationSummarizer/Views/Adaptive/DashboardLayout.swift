import SwiftUI
import UIKit

// MARK: - Size class resolution

/// Coarse layout profile derived from the current size class and device idiom.
///
/// Size classes alone are not enough on iPad: a Slide Over or a narrow Split View
/// window can report a `.regular` width while only offering 320pt of space, so the
/// idiom is used to decide whether a multi column hierarchy is worth offering.
///
/// | Profile    | Devices                                        | Layout                                   |
/// |------------|------------------------------------------------|------------------------------------------|
/// | `compact`  | iPhone / iPod portrait                         | Stack, chips, single column list         |
/// | `medium`   | iPhone landscape, iPad Split View / Slide Over | Stack, adaptive 2 column grid            |
/// | `expanded` | iPad full screen, iPad + Stage Manager         | Sidebar + content grid + detail column   |
enum DashboardLayout: String, CaseIterable, Sendable {
    case compact
    case medium
    case expanded

    /// Resolve the profile from the environment's size classes and the current idiom.
    ///
    /// - Parameters:
    ///   - horizontal: `.compact` on iPhone in portrait and on an iPad in Slide Over
    ///     or a narrow Split View, `.regular` on iPhone in landscape and on a
    ///     full width iPad.
    ///   - vertical: `.compact` in landscape on iPhone, `.regular` in portrait.
    ///   - idiom: `.pad` distinguishes a full width iPad from an iPhone in landscape,
    ///     since both report a regular horizontal size class.
    static func resolve(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        idiom: UIUserInterfaceIdiom = .current
    ) -> DashboardLayout {
        // A compact width never has room for more than one column, whatever the
        // device: iPhone portrait, iPad Slide Over and a narrow Split View all land here.
        guard horizontal == .regular else { return .compact }

        // Regular width. An iPad gets the full multi column hierarchy; an iPhone in
        // landscape only has enough width for a two column grid.
        if idiom == .pad {
            return .expanded
        }

        // Regular width on an iPhone. Confirm it really is landscape, because a
        // window that is short and narrow should still collapse to one column.
        return vertical == .compact ? .medium : .compact
    }

    var isCompact: Bool {
        self == .compact
    }

    /// Only the expanded profile has enough width for sidebar + content + detail.
    var supportsSidebarAndDetail: Bool {
        self == .expanded
    }

    /// Card grids only pay off once the available width exceeds one column.
    var usesAdaptiveGrid: Bool {
        self != .compact
    }

    var title: String {
        switch self {
        case .compact: "Compact — single column"
        case .medium: "Medium — two columns"
        case .expanded: "Expanded — sidebar, grid, detail"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: "iphone"
        case .medium: "iphone.gen3.radiowaves.left.and.right"
        case .expanded: "ipad"
        }
    }
}

extension UIUserInterfaceIdiom {
    /// Idiom of the device the app is currently running on.
    static var current: UIUserInterfaceIdiom {
        UIDevice.current.userInterfaceIdiom
    }
}

// MARK: - Metrics

/// How the selected notification is surfaced after the user taps a card.
enum DetailPresentation: Sendable {
    /// Pushed onto the compact navigation stack.
    case push
    /// Rendered in a persistent trailing column.
    case column
}

/// Spacing, sizing and typography tokens resolved for one layout profile.
///
/// Every value is a token rather than a literal so a card, the AI test panel and
/// the sidebar stay visually consistent no matter which profile is active.
struct DashboardMetrics: Equatable, Sendable {
    // Spacing
    var contentPadding: CGFloat
    var sectionSpacing: CGFloat
    var cardSpacing: CGFloat
    var cardPadding: CGFloat
    var chipSpacing: CGFloat
    var listRowSpacing: CGFloat

    // Shape
    var cardCornerRadius: CGFloat
    var insetCornerRadius: CGFloat

    // Grid
    var gridMinimumColumnWidth: CGFloat
    var gridMaximumColumnWidth: CGFloat

    // Text
    var titleFont: Font
    var cardTitleFont: Font
    var originalTextFont: Font
    var summaryFont: Font
    var badgeFont: Font

    // Controls
    var editorMinimumHeight: CGFloat
    var minimumTapTarget: CGFloat
    var buttonLabelAlignment: HorizontalAlignment

    // Structure
    var showsCategorySidebar: Bool
    var showsDetailColumn: Bool
    var showsInlineStatsHeader: Bool
    var stacksTestCardAboveList: Bool
    var chipsScrollHorizontally: Bool
    var detailPresentation: DetailPresentation

    static func resolve(for layout: DashboardLayout, dynamicTypeSize: DynamicTypeSize = .large) -> DashboardMetrics {
        var metrics = switch layout {
        case .compact:
            DashboardMetrics(
                contentPadding: 16,
                sectionSpacing: 20,
                cardSpacing: 14,
                cardPadding: 16,
                chipSpacing: 8,
                listRowSpacing: 10,
                cardCornerRadius: 18,
                insetCornerRadius: 12,
                gridMinimumColumnWidth: 260,
                gridMaximumColumnWidth: .infinity,
                titleFont: .title.bold(),
                cardTitleFont: .body.weight(.semibold),
                originalTextFont: .subheadline,
                summaryFont: .body.weight(.semibold),
                badgeFont: .caption.weight(.bold),
                editorMinimumHeight: 90,
                minimumTapTarget: 44,
                buttonLabelAlignment: .leading,
                showsCategorySidebar: false,
                showsDetailColumn: false,
                showsInlineStatsHeader: true,
                stacksTestCardAboveList: true,
                chipsScrollHorizontally: true,
                detailPresentation: .push
            )

        case .medium:
            DashboardMetrics(
                contentPadding: 20,
                sectionSpacing: 22,
                cardSpacing: 16,
                cardPadding: 18,
                chipSpacing: 10,
                listRowSpacing: 12,
                cardCornerRadius: 20,
                insetCornerRadius: 14,
                gridMinimumColumnWidth: 300,
                gridMaximumColumnWidth: 460,
                titleFont: .title2.bold(),
                cardTitleFont: .body.weight(.semibold),
                originalTextFont: .subheadline,
                summaryFont: .body.weight(.semibold),
                badgeFont: .caption.weight(.bold),
                editorMinimumHeight: 120,
                minimumTapTarget: 44,
                buttonLabelAlignment: .leading,
                showsCategorySidebar: false,
                showsDetailColumn: false,
                showsInlineStatsHeader: true,
                // Landscape iPhone: the AI test panel sits beside the summary stats
                // instead of consuming the full width above the list.
                stacksTestCardAboveList: false,
                chipsScrollHorizontally: true,
                detailPresentation: .push
            )

        case .expanded:
            DashboardMetrics(
                contentPadding: 24,
                sectionSpacing: 24,
                cardSpacing: 18,
                cardPadding: 20,
                chipSpacing: 12,
                listRowSpacing: 14,
                cardCornerRadius: 22,
                insetCornerRadius: 14,
                gridMinimumColumnWidth: 320,
                gridMaximumColumnWidth: 480,
                titleFont: .largeTitle.bold(),
                cardTitleFont: .headline,
                originalTextFont: .subheadline,
                summaryFont: .title3.weight(.semibold),
                badgeFont: .caption.weight(.bold),
                editorMinimumHeight: 140,
                minimumTapTarget: 44,
                buttonLabelAlignment: .leading,
                showsCategorySidebar: true,
                showsDetailColumn: true,
                showsInlineStatsHeader: false,
                stacksTestCardAboveList: false,
                chipsScrollHorizontally: false,
                detailPresentation: .column
            )
        }

        metrics.applyAccessibilityOverrides(for: dynamicTypeSize)
        return metrics
    }

    /// Accessibility Dynamic Type trades columns and density for legibility.
    private mutating func applyAccessibilityOverrides(for size: DynamicTypeSize) {
        guard size.isAccessibilitySize else { return }

        gridMinimumColumnWidth = 320
        gridMaximumColumnWidth = .infinity
        cardPadding = 20
        sectionSpacing = 24
        cardSpacing = 18
        originalTextFont = .body
        summaryFont = .title3.weight(.semibold)
        editorMinimumHeight = 160
        // Chips and filters wrap into full width rows so labels are never truncated.
        chipsScrollHorizontally = false
    }

    /// Grid configuration handed to `LazyVGrid`.
    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridMinimumColumnWidth, maximum: gridMaximumColumnWidth), spacing: cardSpacing, alignment: .top)]
    }
}

// MARK: - Environment

private struct DashboardLayoutKey: EnvironmentKey {
    static let defaultValue: DashboardLayout = .compact
}

private struct DashboardMetricsKey: EnvironmentKey {
    static let defaultValue: DashboardMetrics = .resolve(for: .compact)
}

extension EnvironmentValues {
    /// Active layout profile for descendants of the dashboard root.
    var dashboardLayout: DashboardLayout {
        get { self[DashboardLayoutKey.self] }
        set { self[DashboardLayoutKey.self] = newValue }
    }

    /// Resolved spacing, sizing and typography tokens for descendants.
    var dashboardMetrics: DashboardMetrics {
        get { self[DashboardMetricsKey.self] }
        set { self[DashboardMetricsKey.self] = newValue }
    }
}

private struct DashboardLayoutModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let layout = DashboardLayout.resolve(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass,
            idiom: .current
        )

        content
            .environment(\.dashboardLayout, layout)
            .environment(\.dashboardMetrics, .resolve(for: layout, dynamicTypeSize: dynamicTypeSize))
    }
}

extension View {
    /// Resolve the adaptive profile once, at the root of the navigation hierarchy.
    ///
    /// The root view still reads the size classes itself because a modifier cannot
    /// change the environment it is attached to; this makes the resolved profile
    /// available to every child that does not take it as a parameter.
    func adaptiveDashboardLayout() -> some View {
        modifier(DashboardLayoutModifier())
    }
}

// MARK: - Shared containers

/// Maximum comfortable measure for body text before line lengths get hard to track.
let readableContentMaxWidth: CGFloat = 760

extension View {
    /// Caps a column at a comfortable measure and centres it.
    ///
    /// The outer `maxWidth: .infinity` frame is what makes the centring work: it
    /// fills the column, then places the capped inner frame in the middle. The
    /// inner frame uses `maxWidth:` (not `containerRelativeFrame`), because a
    /// relative frame resolves against the nearest container — inside a
    /// NavigationSplitView detail column that is the split view itself, which
    /// measures wider than the column and pushes the content out of view.
    func readableContentWidth() -> some View {
        frame(maxWidth: readableContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
