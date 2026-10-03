import SwiftUI

// MARK: - Snapshot clock

/// Injectable "now" used by every time-relative string in the UI.
///
/// `Text(date, style: .relative)` resolves against the wall clock, so the same
/// fixture renders as "3m ago" today and "2h ago" tomorrow. Snapshot tests would
/// therefore start failing purely because time passed. Views read the current
/// instant from here instead, letting tests pin it to a fixed date.
///
/// Production always resolves to `Date.now`, so this is behaviour-preserving.
private struct SnapshotClockKey: EnvironmentKey {
    static let defaultValue: Date = .now
}

extension EnvironmentValues {
    var currentDate: Date {
        get { self[SnapshotClockKey.self] }
        set { self[SnapshotClockKey.self] = newValue }
    }
}

/// Injectable locale used when formatting time-relative strings.
///
/// `RelativeDateTimeFormatter` renders the *same* instant differently per locale:
/// `en_US` yields "3m ago" while `en_IN`/`en_GB` yield "3 min ago". Without pinning
/// it, the rendered card depends on the machine the tests run on, and a baseline
/// recorded on a developer's Mac fails on CI. Tests set this to a fixed locale;
/// production always resolves to `Locale.current`, so this is behaviour-preserving.
private struct SnapshotLocaleKey: EnvironmentKey {
    static let defaultValue: Locale = .current
}

extension EnvironmentValues {
    var currentLocale: Locale {
        get { self[SnapshotLocaleKey.self] }
        set { self[SnapshotLocaleKey.self] = newValue }
    }
}

/// Renders a timestamp relative to an explicit reference instant.
///
/// `RelativeDateTimeFormatter` accepts the reference date as a parameter, so the
/// output depends only on `currentDate`/`currentLocale` and not on when or where
/// the process runs. That determinism is what lets the string appear in a
/// snapshot assertion.
func relativeTimestamp(since timestamp: Date, from reference: Date, locale: Locale = .current) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.locale = locale
    return formatter.localizedString(for: timestamp, relativeTo: reference)
}

// MARK: - Category chips

/// Horizontal filter bar: an "All" chip plus one chip per category.
///
/// Split out of the dashboard so it can be rendered in isolation without a
/// SwiftData store. `selection` is a binding so the dashboard keeps ownership
/// of the filter state.
struct CategoryChipRow: View {
    @Binding var selection: NotificationCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", icon: "square.grid.2x2", active: selection == nil) {
                    selection = nil
                }
                ForEach(NotificationCategory.allCases) { category in
                    chip(title: category.rawValue, icon: category.systemImage, active: selection == category) {
                        selection = category
                    }
                }
            }
        }
    }

    private func chip(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(active ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local AI test card

/// The "Local AI test" panel: input, run button, and the last result.
///
/// Extracted from the dashboard with every piece of state hoisted to a caller
/// supplied value. The dashboard drives it from `@State`; snapshot tests pass
/// literal values, which is what makes the loading / success / error states
/// reachable without waiting on a real Core ML inference.
///
/// `text` is a binding because the field is user editable and the Run button
/// classifies whatever the user typed. A plain `let` here would need
/// `.constant(text)` in the `TextEditor`, which silently discards every keystroke.
struct LocalAITestCard: View {
    @Binding var text: String
    let isRunning: Bool
    let result: String?
    let onRun: () -> Void

    private var canRun: Bool {
        !isRunning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Local AI test", systemImage: "cpu")
                .font(.headline)
            TextEditor(text: $text)
                .frame(minHeight: 90)
                .padding(8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            Button(action: onRun) {
                Label(isRunning ? "Running locally\u{2026}" : "Run Local AI Summary", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRun)

            if let result {
                Text(result)
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Notification card

/// A single summarized notification.
///
/// Takes the SwiftData model directly so the dashboard can bind `isRead`
/// mutations back through the model context.
struct NotificationCardView: View {
    let notification: SummarizedNotification
    @Environment(\.currentDate) private var currentDate
    @Environment(\.currentLocale) private var currentLocale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(notification.category.rawValue, systemImage: notification.category.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
                Spacer()
                // Rendered relative to the injected clock and locale, not the
                // wall clock or the device locale.
                Text(relativeTimestamp(since: notification.timestamp, from: currentDate, locale: currentLocale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(notification.originalText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(notification.summary)
                .font(.body.weight(.semibold))
            HStack {
                Circle().fill(notification.isRead ? Color.secondary : Color.green).frame(width: 7, height: 7)
                Text(notification.isRead ? "Read" : "Unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}
