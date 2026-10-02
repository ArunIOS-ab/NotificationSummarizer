import XCTest
@testable import NotificationSummarizer

/// Covers the deterministic keyword classifier used whenever the Core ML model is unavailable.
final class RuleClassifierTests: XCTestCase {

    func testClassifiesSecurityKeywords() {
        XCTAssertEqual(RuleClassifier.category(for: "Your OTP is 448120"), .security)
        XCTAssertEqual(RuleClassifier.category(for: "New sign-in from a suspicious device"), .security)
        XCTAssertEqual(RuleClassifier.category(for: "Password changed successfully"), .security)
    }

    func testClassifiesFinanceKeywords() {
        XCTAssertEqual(RuleClassifier.category(for: "Charged $42.19 at Whole Foods"), .finance)
        XCTAssertEqual(RuleClassifier.category(for: "Salary credited to your account"), .finance)
        XCTAssertEqual(RuleClassifier.category(for: "Invoice 8842 is due"), .finance)
    }

    func testClassifiesPromotionalKeywords() {
        XCTAssertEqual(RuleClassifier.category(for: "Flash sale: 40% off everything"), .promotional)
        XCTAssertEqual(RuleClassifier.category(for: "Your coupon expires tonight"), .promotional)
    }

    func testClassifiesWorkKeywords() {
        XCTAssertEqual(RuleClassifier.category(for: "Standup moved to 10:30"), .work)
        XCTAssertEqual(RuleClassifier.category(for: "Jira ticket NS-12 assigned to you"), .work)
    }

    func testClassifiesSocialKeywords() {
        XCTAssertEqual(RuleClassifier.category(for: "Ana commented on your post"), .social)
        XCTAssertEqual(RuleClassifier.category(for: "You have a new WhatsApp message"), .social)
    }

    func testFallsBackToPersonalWhenNoKeywordMatches() {
        XCTAssertEqual(RuleClassifier.category(for: "The neighbours are away this weekend"), .personal)
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(RuleClassifier.category(for: "MEETING REMINDER"), .work)
        XCTAssertEqual(RuleClassifier.category(for: "Limited Time Offer"), .promotional)
    }

    /// Security wins over the other buckets because the rules are evaluated in priority order.
    func testSecurityKeywordOutranksWeakerKeyword() {
        XCTAssertEqual(RuleClassifier.category(for: "Fraud alert: suspicious bank transaction on your card"), .security)
    }

    func testEmptyInputIsPersonal() {
        XCTAssertEqual(RuleClassifier.category(for: ""), .personal)
        XCTAssertEqual(RuleClassifier.category(for: "    "), .personal)
    }
}
