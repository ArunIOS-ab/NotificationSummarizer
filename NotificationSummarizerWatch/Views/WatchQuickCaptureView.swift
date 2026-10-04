import SwiftData
import SwiftUI

/// Summarise a notification dictating or typing straight onto the watch.
///
/// This is the capability the phone app cannot offer at all: a notification arrives,
/// the wrist is already raised, and the whole round trip is dictated -> classified ->
/// summarised -> read back, with no phone unlock. Everything runs on device through
/// `WatchSummarizer`, which is the same engine the iOS app uses.
struct WatchQuickCaptureView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var input = ""
    @State private var result: WatchSummaryResult?
    @State private var isRunning = false
    @State private var savedSummary: String?
    @State private var showsTemplates = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    inputField

                    templatesButton

                    runButton

                    if isRunning {
                        ProgressView()
                            .sensoryFeedback(.selection, trigger: isRunning)
                    } else if let result {
                        resultCard(result)
                    } else {
                        idleHint
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Capture")
            // No toolbar here: a `ToolbarItem` inside a page of the root's
            // `.verticalPage` `TabView` collapses that page to a black screen on
            // watchOS. The template picker is a content button instead.
            .confirmationDialog("Sample notifications", isPresented: $showsTemplates, titleVisibility: .visible) {
                ForEach(WatchSampleData.captureTemplates, id: \.self) { template in
                    Button(shortLabel(for: template)) {
                        input = template
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Structure

    private var inputField: some View {
        // `axis: .vertical` is what makes dictation work here: it gives the field more
        // than one line, which is what the watch keyboard raises itself for.
        TextField("Notification text", text: $input, axis: .vertical)
            .font(.footnote)
            .lineLimit(3 ... 8)
            .onSubmit { run() }
    }

    private var templatesButton: some View {
        Button {
            showsTemplates = true
        } label: {
            Label("Use a sample", systemImage: "text.quote")
                .font(.caption2)
        }
        .buttonStyle(.bordered)
    }

    private var runButton: some View {
        Button {
            run()
        } label: {
            Label("Summarise", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(!canRun)
    }

    private var idleHint: some View {
        Text("Dictate or type a notification. It is classified and summarised on this watch.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func resultCard(_ result: WatchSummaryResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: result.category.systemImage)
                    .foregroundStyle(result.category.tint)
                    .accessibilityHidden(true)

                Text(result.category.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.category.tint)

                Spacer(minLength: 0)

                Text("\(result.elapsedMilliseconds) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(result.summary)
                .font(.footnote)

            if let savedSummary {
                Label(savedSummary, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Button {
                    save(result)
                } label: {
                    Label("Save to feed", systemImage: "tray.and.arrow.down")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .sensoryFeedback(.success, trigger: result.id)
    }

    // MARK: - State

    private var canRun: Bool {
        !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Truncates a template for the confirmation dialog.
    ///
    /// The samples are full notification sentences, which a `confirmationDialog` button
    /// on this screen width truncates into an unusable smear. The tap still fills the
    /// whole text into the field, so nothing is lost.
    private func shortLabel(for template: String) -> String {
        let limit = 28
        guard template.count > limit else { return template }
        return String(template.prefix(limit)) + "…"
    }

    private func run() {
        guard canRun else { return }

        Task {
            isRunning = true
            // Clearing the previous verdict first stops the stale summary from staying
            // on screen while the new one is still being computed.
            result = nil
            savedSummary = nil

            let computed = await WatchSummarizer.summarize(input)
            isRunning = false
            guard let computed else { return }
            withAnimation(.snappy) {
                result = computed
            }
        }
    }

    private func save(_ result: WatchSummaryResult) {
        _ = WatchSummarizer.save(result, originalText: input, into: modelContext)
        withAnimation(.snappy) {
            savedSummary = "Added to feed"
        }
    }
}
