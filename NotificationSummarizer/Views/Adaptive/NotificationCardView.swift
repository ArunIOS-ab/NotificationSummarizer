import SwiftData
import SwiftUI

/// A single summarized notification.
///
/// Takes no layout parameter of its own: it reads `resolvedLayout` from the
/// environment, which guarantees the card renders with the same tokens as the
/// container that placed it.
struct NotificationCardView: View {
    let notification: SummarizedNotification
    var isSelected: Bool = false

    @Environment(\.resolvedLayout) private var layout
    @Environment(\.modelContext) private var modelContext
    // Rendered against an injected clock and locale rather than the wall clock, so
    // a snapshot of this card is stable over time and across device locales.
    @Environment(\.currentDate) private var currentDate
    @Environment(\.currentLocale) private var currentLocale

    private var metrics: LayoutMetrics {
        layout.metrics
    }

    private var tint: Color {
        notification.category.tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(notification.summary)
                .font(metrics.summaryFont)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Text(notification.originalText)
                .font(metrics.originalTextFont)
                .foregroundStyle(.secondary)
                .lineLimit(isSelected ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Divider().opacity(0.4)

            footer
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius))
        .onTapGesture { markRead() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.category.rawValue) notification")
        .accessibilityValue(notification.summary)
        .accessibilityHint(isSelected ? "Shows the full notification" : "Marks as read and opens the details")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(notification.category.rawValue, systemImage: notification.category.systemImage)
                .font(metrics.badgeFont)
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12), in: Capsule())
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Text(relativeTimestamp(since: notification.timestamp, from: currentDate, locale: currentLocale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(notification.isRead ? Color.secondary : Color.green)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(notification.isRead ? "Read" : "Unread")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func markRead() {
        guard !notification.isRead else { return }
        notification.isRead = true
        try? modelContext.save()
    }
}

/// Full read view for a single notification.
///
/// Rendered as a pushed destination on narrow widths and as a persistent trailing
/// column on wide ones, so it carries no navigation chrome of its own.
struct NotificationDetailView: View {
    let notification: SummarizedNotification

    @Environment(\.resolvedLayout) private var layout
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var metrics: LayoutMetrics {
        layout.metrics
    }

    private var tint: Color {
        notification.category.tint
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                badge

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Summary")
                    Text(notification.summary)
                        .font(metrics.summaryFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius))

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Original text")
                    Text(notification.originalText)
                        .font(metrics.originalTextFont)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius))

                actions
            }
            // No readable-width cap here: this is the narrowest of the three
            // columns, so capping it makes the detail demand more width than it has
            // and the split view responds by collapsing the sidebar.
            .padding(metrics.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(notification.category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: markRead)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var badge: some View {
        HStack(spacing: 10) {
            Label(notification.category.rawValue, systemImage: notification.category.systemImage)
                .font(metrics.badgeFont)
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tint.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)

            Text(notification.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                notification.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    notification.isRead ? "Mark as unread" : "Mark as read",
                    systemImage: notification.isRead ? "envelope.badge" : "envelope.open"
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: metrics.minimumTapTarget)
            }
            .buttonStyle(.bordered)

            if metrics.detailPresentation == .push {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: metrics.minimumTapTarget)
            }
        }
    }

    private func markRead() {
        guard !notification.isRead else { return }
        notification.isRead = true
        try? modelContext.save()
    }
}

/// Shown in the detail column before a notification is selected.
struct DetailPlaceholderView: View {
    let stats: NotificationStats

    @Environment(\.resolvedLayout) private var layout

    var body: some View {
        ContentUnavailableView {
            Label("No notification selected", systemImage: "rectangle.on.rectangle.slash")
        } description: {
            Text("\(stats.unread) unread of \(stats.total) summarized notifications on this device.")
        }
    }
}

/// Empty state shown when a filter matches nothing.
struct EmptyStateView: View {
    let selectedCategory: NotificationCategory?

    var body: some View {
        ContentUnavailableView {
            Label("Nothing here", systemImage: "tray")
        } description: {
            Text(selectedCategory.map { "No \($0.rawValue.lowercased()) notifications yet." } ?? "No notifications yet.")
        }
        .frame(maxWidth: .infinity)
    }
}
