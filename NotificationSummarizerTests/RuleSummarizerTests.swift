@testable import NotificationSummarizer
import XCTest

/// Covers the deterministic 20-word summarizer used as the offline fallback.
final class RuleSummarizerTests: XCTestCase {
    func testEmptyTextReturnsPlaceholder() {
        XCTAssertEqual(RuleSummarizer.summarize(""), "No actionable notification details available.")
        XCTAssertEqual(RuleSummarizer.summarize("  \n  "), "No actionable notification details available.")
    }

    func testCollapsesWhitespace() {
        let summary = RuleSummarizer.summarize("Board   meeting\n\tmoved to 3pm.")
        XCTAssertEqual(summary, "Board meeting moved to 3pm")
    }

    func testKeepsOnlyFirstSentence() {
        let summary = RuleSummarizer.summarize("Alice invited you to the release party. It starts at 8pm. Bring snacks.")
        XCTAssertEqual(summary, "Alice invited you to the release party")
    }

    func testTruncatesToTwentyWordsWithEllipsis() {
        let text = (1 ... 30).map { "word\($0)" }.joined(separator: " ")
        let summary = RuleSummarizer.summarize(text)

        XCTAssertTrue(summary.hasSuffix("\u{2026}"))
        XCTAssertEqual(summary.split(separator: " ").count, 20, "the ellipsis joins the 20th word")
        XCTAssertTrue(summary.hasPrefix("word1 word2"))
        XCTAssertFalse(summary.contains("word21"), "content past the 20-word limit must be dropped")
    }

    func testExactlyTwentyWordsIsNotTruncated() {
        let text = (1 ... 20).map { "word\($0)" }.joined(separator: " ")
        let summary = RuleSummarizer.summarize(text)

        XCTAssertFalse(summary.hasSuffix("\u{2026}"))
        XCTAssertEqual(summary, text)
    }

    func testExtractsCardChargeWithMerchantAndSuffix() {
        let summary = RuleSummarizer.summarize("You were charged $12.50 at Blue Bottle Coffee on card ending in 4417. Tap to view.")
        XCTAssertEqual(summary, "$12.50 charge at Blue Bottle Coffee on card ending in 4417.")
    }

    func testExtractsCardChargeWithoutSuffix() {
        let summary = RuleSummarizer.summarize("You were charged $99.99 at Example Store. Tap for details.")
        XCTAssertEqual(summary, "$99.99 charge at Example Store.")
    }

    func testCardChargePatternIsCaseInsensitive() {
        let summary = RuleSummarizer.summarize("CHARGED $5.00 AT Corner Deli. Tap to see.")
        XCTAssertEqual(summary, "$5.00 charge at Corner Deli.")
    }

    func testNonChargeTextIsNotForcedIntoChargeTemplate() {
        let summary = RuleSummarizer.summarize("Payment of $10 received at your shop")
        XCTAssertFalse(summary.hasPrefix("$10 charge"))
    }
}
