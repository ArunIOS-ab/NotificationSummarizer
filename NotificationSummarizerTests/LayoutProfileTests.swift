@testable import NotificationSummarizer
import SwiftUI
import XCTest

/// Covers the layout maths that decides the dashboard's structure.
///
/// These are pure functions of their inputs, so they are asserted directly rather
/// than inferred from a rendered image. That matters because the previous design
/// derived layout from the size class alone, which cannot be exercised from a
/// single simulator: one device reports `.regular` at both 688pt and 1366pt.
final class LayoutProfileTests: XCTestCase {
    // MARK: - Width to profile

    func testNarrowWidthsResolveToCompact() {
        for width in [320.0, 390.0, 430.0, 599.0] {
            XCTAssertEqual(
                LayoutProfile.resolve(width: width),
                .compact,
                "\(width)pt should be compact"
            )
        }
    }

    func testMediumWidthsResolveToMedium() {
        for width in [600.0, 744.0, 834.0, 899.0] {
            XCTAssertEqual(
                LayoutProfile.resolve(width: width),
                .medium,
                "\(width)pt should be medium"
            )
        }
    }

    func testWideWidthsResolveToExpanded() {
        for width in [900.0, 1024.0, 1366.0] {
            XCTAssertEqual(
                LayoutProfile.resolve(width: width),
                .expanded,
                "\(width)pt should be expanded"
            )
        }
    }

    /// The threshold itself belongs to the lower profile, so the two ranges tile
    /// the whole width space with no gap and no overlap.
    func testBreakpointsAreContiguous() {
        XCTAssertEqual(LayoutProfile.resolve(width: LayoutProfile.mediumThreshold - 1), .compact)
        XCTAssertEqual(LayoutProfile.resolve(width: LayoutProfile.mediumThreshold), .medium)
        XCTAssertEqual(LayoutProfile.resolve(width: LayoutProfile.expandedThreshold - 1), .medium)
        XCTAssertEqual(LayoutProfile.resolve(width: LayoutProfile.expandedThreshold), .expanded)
    }

    /// An unmeasured width falls back to the one layout that fits everywhere.
    func testUnmeasuredWidthIsCompact() {
        XCTAssertEqual(LayoutProfile.resolve(width: nil), .compact)
        XCTAssertEqual(LayoutProfile.resolve(width: 0), .compact)
        XCTAssertEqual(LayoutProfile.resolve(width: -100), .compact)
    }

    /// The regression the width-based design exists to prevent: a 2/3 Split View
    /// iPad reports a regular size class but only offers 688pt, which is far too
    /// narrow for three columns.
    func testNarrowSplitViewWidthDoesNotEarnThreeColumns() {
        XCTAssertEqual(LayoutProfile.resolve(width: 688), .medium)
        XCTAssertFalse(LayoutProfile.resolve(width: 688).supportsSplitColumns)
    }

    func testOnlyExpandedSupportsSplitColumns() {
        XCTAssertFalse(LayoutProfile.compact.supportsSplitColumns)
        XCTAssertFalse(LayoutProfile.medium.supportsSplitColumns)
        XCTAssertTrue(LayoutProfile.expanded.supportsSplitColumns)
    }

    // MARK: - Size class fallback

    /// Before the first measurement the size class picks a starting point so an
    /// iPad does not flash the compact layout.
    func testSizeClassFallbackPicksAProfile() {
        XCTAssertEqual(
            LayoutProfile.resolve(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular,
                idiom: .pad
            ),
            .compact
        )
        XCTAssertEqual(
            LayoutProfile.resolve(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                idiom: .pad
            ),
            .expanded
        )
        XCTAssertEqual(
            LayoutProfile.resolve(
                horizontalSizeClass: .regular,
                verticalSizeClass: .compact,
                idiom: .phone
            ),
            .medium
        )
        XCTAssertEqual(
            LayoutProfile.resolve(
                horizontalSizeClass: nil,
                verticalSizeClass: nil,
                idiom: .unspecified
            ),
            .compact
        )
    }

    /// A measured width always beats the size class guess, which is what makes
    /// Split View and Slide Over work.
    func testMeasuredWidthOverridesSizeClassGuess() {
        let layout = ResolvedLayout.resolve(
            width: 688,
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            idiom: .pad,
            dynamicTypeSize: .large
        )
        XCTAssertEqual(layout.profile, .medium, "688pt is too narrow for the expanded layout")
    }

    // MARK: - Column resolution

    func testColumnCountGrowsWithWidth() {
        let spacing: CGFloat = 18
        let ideal = ColumnResolver.idealColumnWidth

        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 320, spacing: spacing), 1)
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 700, spacing: spacing), 2)
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 1040, spacing: spacing), 3)
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 1400, spacing: spacing), 4)
    }

    /// Past the ceiling, extra width widens the cards rather than adding columns
    /// narrower than their own category badge.
    func testColumnCountIsCapped() {
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 4000, spacing: 18), ColumnResolver.maximumColumns)
    }

    /// Every width must yield at least one column, or the grid renders empty.
    func testColumnCountNeverDropsBelowOne() {
        for width in [1.0, 10.0, 100.0, 319.0] {
            XCTAssertEqual(ColumnResolver.columnCount(forWidth: width, spacing: 18), 1, "\(width)pt")
        }
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 0, spacing: 18), 1)
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: -50, spacing: 18), 1)
    }

    /// The spacing arithmetic must neither drop a column that fits nor invent one
    /// that does not.
    ///
    /// Three columns of 320pt need two 18pt gaps, so the exact threshold is
    /// `320 * 3 + 18 * 2 = 996`. One point either side must straddle it.
    func testColumnCountAccountsForGaps() {
        let spacing: CGFloat = 18
        let ideal = ColumnResolver.idealColumnWidth
        let exactThree = (ideal * 3) + (spacing * 2)

        XCTAssertEqual(
            ColumnResolver.columnCount(forWidth: exactThree - 1, spacing: spacing),
            2,
            "one point short of three columns must still yield two"
        )
        XCTAssertEqual(
            ColumnResolver.columnCount(forWidth: exactThree, spacing: spacing),
            3,
            "exactly enough for three columns must yield three"
        )
    }

    func testZeroMinimumWidthStillReturnsOneColumn() {
        XCTAssertEqual(ColumnResolver.columnCount(forWidth: 900, spacing: 18, minimumColumnWidth: 0), 1)
    }

    // MARK: - Metrics

    func testOnlyExpandedProfileGetsSidebarAndDetail() {
        XCTAssertFalse(LayoutMetrics.resolve(for: .compact).showsCategorySidebar)
        XCTAssertFalse(LayoutMetrics.resolve(for: .medium).showsCategorySidebar)
        XCTAssertTrue(LayoutMetrics.resolve(for: .expanded).showsCategorySidebar)

        XCTAssertFalse(LayoutMetrics.resolve(for: .compact).showsDetailColumn)
        XCTAssertFalse(LayoutMetrics.resolve(for: .medium).showsDetailColumn)
        XCTAssertTrue(LayoutMetrics.resolve(for: .expanded).showsDetailColumn)
    }

    func testDetailPresentationMatchesTheStructure() {
        XCTAssertEqual(LayoutMetrics.resolve(for: .compact).detailPresentation, .push)
        XCTAssertEqual(LayoutMetrics.resolve(for: .medium).detailPresentation, .push)
        XCTAssertEqual(LayoutMetrics.resolve(for: .expanded).detailPresentation, .column)
    }

    func testEveryProfileMeetsTheMinimumTapTarget() {
        for profile in LayoutProfile.allCases {
            XCTAssertGreaterThanOrEqual(
                LayoutMetrics.resolve(for: profile).minimumTapTarget,
                44,
                "\(profile.rawValue) must keep a 44pt tap target"
            )
        }
    }

    func testGridColumnsMatchTheResolvedColumnCount() {
        let metrics = LayoutMetrics.resolve(for: .expanded)
        let expected = ColumnResolver.columnCount(forWidth: 1040, spacing: metrics.cardSpacing)
        XCTAssertEqual(metrics.gridColumns(forWidth: 1040).count, expected)
    }

    // MARK: - Accessibility

    /// Accessibility Dynamic Type widens the minimum column, so a size that fits
    /// three columns at the default type size must not still fit three at AX5.
    func testAccessibilityTypeWidensColumns() {
        let standard = LayoutMetrics.resolve(for: .expanded, dynamicTypeSize: .large)
        let accessible = LayoutMetrics.resolve(for: .expanded, dynamicTypeSize: .accessibility3)

        XCTAssertGreaterThan(accessible.minimumColumnWidth, standard.minimumColumnWidth)
        XCTAssertLessThanOrEqual(
            accessible.gridColumns(forWidth: 1040).count,
            standard.gridColumns(forWidth: 1040).count,
            "accessibility sizes must not fit more columns than the default"
        )
    }

    func testAccessibilityTypeUnwrapsTheFilterRow() {
        XCTAssertTrue(LayoutMetrics.resolve(for: .compact, dynamicTypeSize: .large).filtersScrollHorizontally)
        XCTAssertFalse(
            LayoutMetrics.resolve(for: .compact, dynamicTypeSize: .accessibility1).filtersScrollHorizontally,
            "scrolling chips clip long labels at accessibility sizes"
        )
    }

    // MARK: - Resolved layout consistency

    /// The profile, tokens and width must agree; a mismatch is what previously let
    /// the sidebar, grid and detail column each disagree about the column count.
    func testResolvedLayoutIsInternallyConsistent() {
        for width in [320.0, 700.0, 1024.0] {
            let layout = ResolvedLayout.resolve(
                width: width,
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                idiom: .pad,
                dynamicTypeSize: .large
            )
            XCTAssertEqual(layout.width, width)
            XCTAssertEqual(layout.metrics.showsCategorySidebar, layout.profile.supportsSplitColumns)
            XCTAssertEqual(layout.metrics.detailPresentation == .column, layout.profile.supportsSplitColumns)
        }
    }
}
