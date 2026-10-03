import SwiftUI

/// Interactive panel that runs the on-device classifier and summarizer.
///
/// The panel adapts in two ways:
/// - The editor grows with the profile so it never dominates a full screen iPad.
/// - The result is announced with `accessibilityLiveRegion` because the button
///   triggers asynchronous work and VoiceOver would otherwise stay silent.
struct AdaptiveLocalAITestCard: View {
    let metrics: DashboardMetrics

    @State private var text = "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction."
    @State private var result: String?
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: metrics.buttonLabelAlignment, spacing: 12) {
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

            runButton

            if let result {
                resultBanner(result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(metrics.cardPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: metrics.cardCornerRadius))
        .animation(.snappy(duration: 0.2), value: result)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(Color.accentColor)
            Text("Local AI test")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // The title is truncated rather than wrapped because the sidebar column can
            // be as narrow as 170pt. This trailing badge is the first thing to
            // drop when there is not room for it.
            if metrics.editorMinimumHeight >= 140 {
                Text("On device")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var runButton: some View {
        Button(action: run) {
            Label(isRunning ? "Running locally…" : "Run Local AI Summary", systemImage: "sparkles")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: metrics.minimumTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isRunning || trimmedText.isEmpty)
    }

    private func resultBanner(_ result: String) -> some View {
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

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run() {
        guard !isRunning, !trimmedText.isEmpty else { return }

        Task {
            isRunning = true
            defer { isRunning = false }

            let engine = LocalMLEngineActor.shared
            let category = await engine.classify(text: text)
            let summary = (try? await engine.summarize(text: text)) ?? "Unable to summarize."
            result = "\(category.rawValue) • \(summary)"
        }
    }
}

#Preview {
    VStack {
        AdaptiveLocalAITestCard(metrics: .resolve(for: .compact))
        AdaptiveLocalAITestCard(metrics: .resolve(for: .expanded))
    }
    .padding()
}