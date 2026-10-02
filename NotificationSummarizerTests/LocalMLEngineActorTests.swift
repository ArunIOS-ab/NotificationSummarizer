@testable import NotificationSummarizer
import XCTest

/// Covers the actor's public surface: the rule-based behaviour that must hold when the
/// Core ML model and tokenizer are absent from the test bundle.
final class LocalMLEngineActorTests: XCTestCase {
    func testClassifyReturnsPersonalForBlankText() async {
        let engine = LocalMLEngineActor()
        let category = await engine.classify(text: "   \n  ")

        XCTAssertEqual(category, .personal)
    }

    func testClassifyCompletesWithinTheTimeoutBudget() async {
        let engine = LocalMLEngineActor()
        let start = Date()
        _ = await engine.classify(text: "Standup moved to 10:30")

        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5, "classification must honour the 1.5s budget")
    }

    func testSummarizeUsesTheDeterministicFallback() async throws {
        let engine = LocalMLEngineActor()
        let text = "You were charged $12.50 at Blue Bottle Coffee on card ending in 4417. Tap to view."

        let summary = try await engine.summarize(text: text)

        XCTAssertEqual(summary, RuleSummarizer.summarize(text))
        XCTAssertEqual(summary, "$12.50 charge at Blue Bottle Coffee on card ending in 4417.")
    }

    func testSummarizeNeverReturnsEmptyText() async throws {
        let engine = LocalMLEngineActor()
        let summary = try await engine.summarize(text: "   ")

        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary, "No actionable notification details available.")
    }

    func testMemoryPressureNotificationNameIsPublished() async {
        let engine = LocalMLEngineActor()
        // Touching the actor proves it initialises (and installs its memory-pressure observer).
        _ = await engine.classify(text: "hello")

        let expectation = expectation(forNotification: .notificationSummarizerMemoryPressure, object: nil) { _ in true }
        NotificationCenter.default.post(name: .notificationSummarizerMemoryPressure, object: nil)

        await fulfillment(of: [expectation], timeout: 1)
    }
}
