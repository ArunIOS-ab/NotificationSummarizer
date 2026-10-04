import SwiftUI

/// One notification in the watch feed.
///
/// A watch row gets roughly two lines of text, so the information order is deliberate:
/// category first (colour + glyph, readable without reading the label), then the
/// summary, then the age. The original notification text is intentionally *not* here --
/// it is one tap away in `WatchDetailView`, and showing it here would push the summary
/// -- the reason the screen exists -- off the row.
struct WatchNotificationRow: View {
    let notification: SummarizedNotification

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.category.systemImage)
                .font(.title3)
                .foregroundStyle(notification.category.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.summary)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(notification.category.rawValue)
                    Text("·")
                    Text(notification.timestamp, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Unread marker instead of a trailing chevron: `NavigationLink` already
            // draws its own, and a second glyph on a 40pt-tall row is noise.
            if !notification.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.category.rawValue), \(notification.summary)")
        .accessibilityValue(notification.isRead ? "Read" : "Unread")
    }
}
