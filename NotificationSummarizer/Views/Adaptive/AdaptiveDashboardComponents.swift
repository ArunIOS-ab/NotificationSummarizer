import SwiftData
import SwiftUI

/// Counts derived from the current result set, used by the compact stats header
/// and the iPad sidebar so both surfaces always agree.
struct NotificationStats: Equatable {
    var total: Int
    var unread: Int
    var countsByCategory: [NotificationCategory: Int]

    static func make(from notifications: [SummarizedNotification]) -> NotificationStats {
        var counts: [NotificationCategory: Int] = [:]
        var unread = 0

        for notification in notifications {
            counts[notification.category, default: 0] += 1
            if !notification.isRead { unread += 1 }
        }

        return NotificationStats(
            total: notifications.count,
            unread: unread,
            countsByCategory: counts
        )
    }

    func count(for category: NotificationCategory?) -> Int {
        guard let category else { return total }
        return countsByCategory[category, default: 0]
    }
}

/// A single labelled count. Laid out with a fixed leading column so the numbers
/// line up between the compact header and the sidebar rows.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            // The icon is allowed to shrink rather than squeezing the value and
            // label, which is what truncated them to "Un..." and "Ca..." when the
            // three tiles shared a narrow column.
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(minWidth: 22, maxWidth: 22)
                .frame(minHeight: 22, maxHeight: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .layoutPriority(-1)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Row of summary statistics.
///
/// - Compact: `LazyVGrid` of stacked tiles so three tiles fit the narrow width.
/// - Medium and up: a single `HStack` with equal-width tiles.
struct StatsHeaderView: View {
    let stats: NotificationStats
    let metrics: DashboardMetrics

    var body: some View {
        // Three equal columns at every size: equal `GridItem`s keep the labels on
        // one baseline row, whereas a flexible HStack divides width by content and
        // truncates the shorter labels ("Total" -> "T...").
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: metrics.cardSpacing), count: 3),
            spacing: metrics.cardSpacing
        ) {
            tiles
        }
        .padding(metrics.cardPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius))
    }

    @ViewBuilder
    private var tiles: some View {
        StatTile(
            title: "Total",
            value: stats.total.formatted(),
            systemImage: "number",
            tint: .accentColor
        )
        StatTile(
            title: "Unread",
            value: stats.unread.formatted(),
            systemImage: "circle.fill",
            tint: .green
        )
        StatTile(
            title: "Types",
            value: activeCategoryCount.formatted(),
            systemImage: "square.grid.2x2.fill",
            tint: .purple
        )
    }

    private var activeCategoryCount: Int {
        NotificationCategory.allCases.filter { stats.countsByCategory[$0] ?? 0 > 0 }.count
    }
}

/// Filters the result set by category.
///
/// - Compact / medium: a horizontally scrolling capsule row, which is the
///   familiar iOS pattern for a filter that lives above the content.
/// - Expanded: a wrapping `Layout` that lets every option breathe on iPad.
///   Accessibility Dynamic Type also switches to this wrapping layout so long
///   labels are never clipped.
struct CategoryFilterView: View {
    @Binding var selection: NotificationCategory?
    let stats: NotificationStats
    let metrics: DashboardMetrics

    var body: some View {
        if metrics.chipsScrollHorizontally {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: metrics.chipSpacing) {
                    options
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        } else {
            WrappingLayout(spacing: metrics.chipSpacing, lineSpacing: metrics.chipSpacing) {
                options
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        chip(title: "All", icon: "square.grid.2x2", count: stats.total, active: selection == nil) {
            selection = nil
        }

        ForEach(NotificationCategory.allCases) { category in
            chip(
                title: category.rawValue,
                icon: category.systemImage,
                count: stats.count(for: category),
                active: selection == category
            ) {
                selection = selection == category ? nil : category
            }
        }
    }

    private func chip(title: String, icon: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if count > 0, metrics.contentPadding <= 24 {
                    Text(count.formatted())
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((active ? Color.white : Color.secondary).opacity(active ? 0.25 : 0.15), in: Capsule())
                }
            }
            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .frame(minHeight: metrics.minimumTapTarget)
            .background(
                active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(count.formatted())
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// Minimal flow layout: stacks children left to right and wraps onto a new row
/// when the next child would exceed the proposed width.
///
/// Written by hand rather than pulled from a package so the project stays
/// dependency free, and used only on iPad / accessibility sizes where the
/// filter row genuinely has room to wrap.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)

        let height = rows.reduce(0) { total, row in
            total + row.height
        } + lineSpacing * CGFloat(max(0, rows.count - 1))

        return CGSize(width: proposal.width ?? maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX

            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }

            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}