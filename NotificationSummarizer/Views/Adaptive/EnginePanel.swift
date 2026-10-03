import SwiftUI

/// Interactive panel that runs the on-device classifier and summarizer.
///
/// State is supplied by the caller rather than owned here, for two reasons:
/// the dashboard decides when a run is in flight, and snapshot tests need to
/// render the idle, loading, success and error states without driving a real
/// Core ML inference.
struct EnginePanel: View {
    @Binding var text: String
    let isRunning: Bool
    let result: String?

    @Environment(\.resolvedLayout) private var layout

    private var metrics: LayoutMetrics {
        layout.metrics
    }

    private var canRun: Bool {
        !isRunning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TextEditor(text: $text)
                .font(.subheadline)
                .frame(minHeight: metrics.editorMinimumHeight)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: metrics.insetCornerRadius)
                )
                .accessibilityLabel("Text to classify and summarize")

            if let result {
                Text(result)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.accentColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: metrics.insetCornerRadius)
                    )
                    .accessibilityLabel("Result")
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(metrics.cardPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(Color.accentColor)
            Text("Local AI test")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            // The first thing to drop when the sidebar column is narrow.
            if metrics.editorMinimumHeight >= 140 {
                Text("On device")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// The button that triggers a run, kept separate so the panel stays renderable
/// without an action and the sidebar can host the control directly.
struct EngineRunButton: View {
    let isRunning: Bool
    let canRun: Bool
    let action: () -> Void

    @Environment(\.resolvedLayout) private var layout

    var body: some View {
        Button(action: action) {
            Label(isRunning ? "Running locally…" : "Run Local AI Summary", systemImage: "sparkles")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: layout.metrics.minimumTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canRun)
    }
}
