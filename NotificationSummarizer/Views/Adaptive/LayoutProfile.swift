import CoreGraphics
import SwiftUI

// MARK: - Device idiom

/// The idiom of the device the app is running on.
///
/// Wrapped in its own enum rather than reading `UIDevice.current` directly, so the
/// layout maths stays a pure function of its inputs and can be unit tested without
/// a simulator.
enum DeviceIdiom: String, Sendable, CaseIterable {
    case phone
    case pad
    case unspecified

    init(_ idiom: UIUserInterfaceIdiom) {
        switch idiom {
        case .phone: self = .phone
        case .pad: self = .pad
        default: self = .unspecified
        }
    }
}

// MARK: - Layout profile

/// The structural layout the dashboard uses.
///
/// The profile is derived from the **measured width** of the dashboard container,
/// not from the size class alone. Size class is only a coarse hint: it reports
/// `.regular` for everything from a 2/3 Split View iPad (688pt) to a 13" iPad in
/// full screen (1366pt), which is far too wide a range to drive a fixed design.
/// Measuring the width means Split View, Slide Over, Stage Manager and any future
/// device each get the layout that actually fits.
///
/// | Profile    | Width      | Structure                                  |
/// |------------|------------|--------------------------------------------|
/// | `compact`  | `< 600pt`  | Stack, one column, filters as scrolling chips |
/// | `medium`   | `600–899pt`| Two column grid, engine panel docked beside   |
/// | `expanded` | `>= 900pt` | Sidebar + content grid + detail column         |
enum LayoutProfile: String, CaseIterable, Sendable {
    case compact
    case medium
    case expanded

    /// Lower bound, in points, at which this profile begins to apply.
    ///
    /// 600pt is the narrowest width where a sidebar and a content column can both
    /// be readable; 900pt is where a third (detail) column still leaves enough
    /// room for the content grid to show more than one card per row.
    static let mediumThreshold: CGFloat = 600
    static let expandedThreshold: CGFloat = 900

    /// Resolve the profile from the measured container width.
    ///
    /// - Parameter width: The width actually available to the dashboard, in points.
    ///   Pass `nil` when it has not been measured yet (first layout pass); the
    ///   compact profile is the safe default because it is the only one that fits
    ///   everywhere.
    static func resolve(width: CGFloat?) -> LayoutProfile {
        guard let width, width > 0 else { return .compact }
        if width >= expandedThreshold {
            return .expanded
        }
        if width >= mediumThreshold {
            return .medium
        }
        return .compact
    }

    /// Resolve from size class and idiom alone.
    ///
    /// Used as the pre-measurement guess so the first frame already picks a
    /// sensible structure instead of flashing the compact layout on an iPad. Maps
    /// the size class onto a representative width: `.compact` is always narrower
    /// than `mediumThreshold`, and `.regular` to a width that keeps a full width
    /// iPad on `expanded` while an iPhone in landscape stays in `medium`.
    static func resolve(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        idiom: DeviceIdiom
    ) -> LayoutProfile {
        guard horizontalSizeClass == .regular else { return .compact }

        // Regular width. A pad gets the widest design; a phone in landscape is
        // tall-short rather than wide, so it only earns two columns.
        if idiom == .pad {
            return verticalSizeClass == .compact ? .expanded : .expanded
        }
        return .medium
    }

    /// True when the profile has room for the sidebar + content + detail hierarchy.
    var supportsSplitColumns: Bool {
        self == .expanded
    }

    var title: String {
        switch self {
        case .compact: "Compact — one column"
        case .medium: "Medium — two columns"
        case .expanded: "Expanded — sidebar, grid, detail"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: "iphone"
        case .medium: "iphone.landscape"
        case .expanded: "ipad"
        }
    }
}

// MARK: - Column resolution

/// How many columns of notification cards fit in a given width.
///
/// This is the same arithmetic a flow layout performs: divide the available width
/// by the ideal column width and clamp. Keeping it a pure function means the
/// behaviour can be asserted directly in unit tests instead of being inferred from
/// a rendered screenshot.
enum ColumnResolver {
    /// Ideal width of a single card column before it becomes unreadably narrow.
    static let idealColumnWidth: CGFloat = 320

    /// Hard ceiling on columns. Past four, cards become narrower than their own
    /// category badge and the grid stops reading as a list.
    static let maximumColumns = 4

    /// Number of columns that fit in `width`.
    ///
    /// `AdaptiveCardGrid` renders with `GridItem(.adaptive(minimum:))` so SwiftUI
    /// resolves the count during layout. This mirrors that arithmetic so the column
    /// counts the layout produces are asserted directly rather than inferred from a
    /// rendered image.
    ///
    /// - Parameters:
    ///   - width: Available width in points, excluding padding.
    ///   - spacing: Gap between columns.
    ///   - minimumColumnWidth: Below this a column stops being usable.
    /// - Returns: At least 1, at most `maximumColumns`.
    static func columnCount(
        forWidth width: CGFloat,
        spacing: CGFloat,
        minimumColumnWidth: CGFloat = idealColumnWidth
    ) -> Int {
        guard width > 0, minimumColumnWidth > 0 else { return 1 }

        // Each column costs its own width plus the gap that follows it, so the
        // number of *gaps* is one fewer than the number of columns.
        let columnsThatFit = Int((width + spacing) / (minimumColumnWidth + spacing))
        return max(1, min(columnsThatFit, maximumColumns))
    }
}

// MARK: - Design tokens

/// How the selected notification is surfaced after the user taps a card.
enum DetailPresentation: Sendable {
    /// Pushed onto the compact navigation stack.
    case push
    /// Rendered in a persistent trailing column.
    case column
}

/// Spacing, sizing and typography resolved for one profile.
///
/// Every value is a token rather than a literal so a card, the AI panel and the
/// sidebar stay visually consistent at every width.
struct LayoutMetrics: Equatable, Sendable {
    // Spacing
    var contentPadding: CGFloat
    var sectionSpacing: CGFloat
    var cardSpacing: CGFloat
    var cardPadding: CGFloat
    var chipSpacing: CGFloat

    // Shape
    var cardCornerRadius: CGFloat
    var insetCornerRadius: CGFloat

    // Text
    var summaryFont: Font
    var originalTextFont: Font
    var badgeFont: Font

    // Controls
    var editorMinimumHeight: CGFloat
    var minimumTapTarget: CGFloat

    // Structure
    var showsCategorySidebar: Bool
    var showsDetailColumn: Bool
    var stacksEnginePanelAboveList: Bool
    var filtersScrollHorizontally: Bool
    var detailPresentation: DetailPresentation

    /// Minimum width below which a card column stops being usable.
    var minimumColumnWidth: CGFloat

    static func resolve(
        for profile: LayoutProfile,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> LayoutMetrics {
        var metrics = switch profile {
        case .compact:
            LayoutMetrics(
                contentPadding: 16,
                sectionSpacing: 20,
                cardSpacing: 14,
                cardPadding: 16,
                chipSpacing: 8,
                cardCornerRadius: 18,
                insetCornerRadius: 12,
                summaryFont: .body.weight(.semibold),
                originalTextFont: .subheadline,
                badgeFont: .caption.weight(.bold),
                editorMinimumHeight: 90,
                minimumTapTarget: 44,
                showsCategorySidebar: false,
                showsDetailColumn: false,
                stacksEnginePanelAboveList: true,
                filtersScrollHorizontally: true,
                detailPresentation: .push,
                minimumColumnWidth: ColumnResolver.idealColumnWidth
            )

        case .medium:
            LayoutMetrics(
                contentPadding: 20,
                sectionSpacing: 22,
                cardSpacing: 16,
                cardPadding: 18,
                chipSpacing: 10,
                cardCornerRadius: 20,
                insetCornerRadius: 14,
                summaryFont: .body.weight(.semibold),
                originalTextFont: .subheadline,
                badgeFont: .caption.weight(.bold),
                editorMinimumHeight: 120,
                minimumTapTarget: 44,
                showsCategorySidebar: false,
                showsDetailColumn: false,
                // Wide but short: the engine panel sits beside the list instead of
                // eating the full width above it.
                stacksEnginePanelAboveList: false,
                filtersScrollHorizontally: true,
                detailPresentation: .push,
                minimumColumnWidth: ColumnResolver.idealColumnWidth
            )

        case .expanded:
            LayoutMetrics(
                contentPadding: 24,
                sectionSpacing: 24,
                cardSpacing: 18,
                cardPadding: 20,
                chipSpacing: 12,
                cardCornerRadius: 22,
                insetCornerRadius: 14,
                summaryFont: .title3.weight(.semibold),
                originalTextFont: .subheadline,
                badgeFont: .caption.weight(.bold),
                editorMinimumHeight: 140,
                minimumTapTarget: 44,
                showsCategorySidebar: true,
                showsDetailColumn: true,
                stacksEnginePanelAboveList: false,
                filtersScrollHorizontally: false,
                detailPresentation: .column,
                minimumColumnWidth: ColumnResolver.idealColumnWidth
            )
        }

        metrics.applyAccessibilityOverrides(for: dynamicTypeSize)
        return metrics
    }

    /// Accessibility Dynamic Type trades density for legibility.
    private mutating func applyAccessibilityOverrides(for size: DynamicTypeSize) {
        guard size.isAccessibilitySize else { return }

        // Bigger text needs wider cards, and filters must wrap so labels never clip.
        minimumColumnWidth = 380
        cardPadding = 20
        sectionSpacing = 24
        cardSpacing = 18
        originalTextFont = .body
        summaryFont = .title3.weight(.semibold)
        editorMinimumHeight = 160
        filtersScrollHorizontally = false
    }

    /// Explicit grid columns for a measured width.
    ///
    /// Returns a fixed count rather than an `.adaptive` minimum so the number of
    /// columns is a pure function of the width, which is what makes the layout
    /// assertable in unit tests.
    func gridColumns(forWidth width: CGFloat) -> [GridItem] {
        let count = ColumnResolver.columnCount(
            forWidth: width,
            spacing: cardSpacing,
            minimumColumnWidth: minimumColumnWidth
        )
        return Array(
            repeating: GridItem(.flexible(), spacing: cardSpacing, alignment: .top),
            count: count
        )
    }
}

// MARK: - Resolved environment

/// The complete layout decision for one render pass.
///
/// Bundling the profile, its tokens and the measured width keeps the three in
/// sync: a view cannot read a `profile` that disagrees with the `width` the
/// columns were computed from.
struct ResolvedLayout: Equatable, Sendable {
    var profile: LayoutProfile
    var metrics: LayoutMetrics
    var width: CGFloat

    static func resolve(
        width: CGFloat?,
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        idiom: DeviceIdiom,
        dynamicTypeSize: DynamicTypeSize
    ) -> ResolvedLayout {
        // Prefer the measured width. Before the first measurement falls back to the
        // size class guess so an iPad does not briefly render the compact layout.
        let profile = width.flatMap { $0 > 0 ? LayoutProfile.resolve(width: $0) : nil }
            ?? LayoutProfile.resolve(
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass,
                idiom: idiom
            )

        // Until the width is known, assume it spans the profile so the first frame
        // already lays out as many columns as that profile eventually allows.
        let effectiveWidth = width ?? LayoutProfile.expandedThreshold

        return ResolvedLayout(
            profile: profile,
            metrics: .resolve(for: profile, dynamicTypeSize: dynamicTypeSize),
            width: effectiveWidth
        )
    }
}

// MARK: - View plumbing

private struct ResolvedLayoutKey: EnvironmentKey {
    static let defaultValue = ResolvedLayout.resolve(
        width: nil,
        horizontalSizeClass: .compact,
        verticalSizeClass: .regular,
        idiom: .unspecified,
        dynamicTypeSize: .large
    )
}

extension EnvironmentValues {
    /// Active layout decision for descendants of the dashboard root.
    var resolvedLayout: ResolvedLayout {
        get { self[ResolvedLayoutKey.self] }
        set { self[ResolvedLayoutKey.self] = newValue }
    }
}

extension View {
    /// Inject a layout resolved from explicit values.
    ///
    /// Used by snapshot tests, which need a specific profile without depending on
    /// the simulator they happen to run on. Production code should go through
    /// `AdaptiveLayoutHost`, which measures the real width.
    func resolvedLayout(_ layout: ResolvedLayout) -> some View {
        environment(\.resolvedLayout, layout)
    }
}

// MARK: - Width-agnostic grid

/// A grid of notification cards that fills whatever width it is given.
///
/// Uses `GridItem(.adaptive(minimum:))` rather than a column count computed from
/// the window width. The grid is usually rendered inside a column narrower than
/// the window -- the content column of a `NavigationSplitView` is a fraction of it
/// once the sidebar and detail column have taken their share -- and an explicit
/// count derived from the window width produced three columns in a 287pt column,
/// squeezing each card to about 140pt and wrapping the text one word per line.
///
/// The adaptive minimum lets SwiftUI resolve the column count in the same layout
/// pass that places the cards, the way a flow layout does, so it is always
/// correct for the container it lands in: Split View, Slide Over and Stage Manager
/// included, none of which can be inferred from the size class alone.
///
/// `ColumnResolver.columnCount(forWidth:spacing:)` models the same arithmetic as a
/// pure function so the resulting column counts remain unit testable.
struct AdaptiveCardGrid<Content: View>: View {
    @Environment(\.resolvedLayout) private var layout
    @ViewBuilder private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let metrics = layout.metrics

        LazyVGrid(
            columns: [GridItem(
                .adaptive(minimum: metrics.minimumColumnWidth),
                spacing: metrics.cardSpacing,
                alignment: .top
            )],
            alignment: .leading,
            spacing: metrics.cardSpacing
        ) {
            content()
        }
    }
}
