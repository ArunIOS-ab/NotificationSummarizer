import SwiftData
import SwiftUI

/// Full view of one notification: the summary that matters, plus the raw text it came
/// from.
///
/// Takes the `@Model` object rather than a snapshot of its fields so that marking it
/// read on this screen updates the feed row behind it.
struct WatchDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let notification: SummarizedNotification

    @State private var showsOriginal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                Text(notification.summary)
                    .font(.footnote)

                Divider()

                Text(notification.originalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // The original text is an order of magnitude longer than the
                    // summary, so it is collapsed until explicitly asked for.
                    .lineLimit(showsOriginal ? nil : 3)

                Button(showsOriginal ? "Show less" : "Show original") {
                    showsOriginal.toggle()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                HStack(spacing: 8) {
                    // Read state and delete both live in the content, not a toolbar:
                    // the detail view is pushed inside a page of the root's
                    // `.verticalPage` `TabView`, and a `ToolbarItem` there collapses
                    // the page to a black screen on watchOS.
                    Button {
                        notification.isRead.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            notification.isRead ? "Mark unread" : "Mark read",
                            systemImage: notification.isRead ? "circlebadge" : "checkmark.circle"
                        )
                    }
                    .font(.caption2)

                    Button(role: .destructive) {
                        modelContext.delete(notification)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(notification.category.rawValue)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: notification.category.systemImage)
                .foregroundStyle(notification.category.tint)
                .accessibilityHidden(true)

            Text(notification.category.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(notification.category.tint)

            Text("·")
                .foregroundStyle(.secondary)

            Text(notification.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}
