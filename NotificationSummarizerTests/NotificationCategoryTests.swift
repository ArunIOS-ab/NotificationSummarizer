import XCTest
@testable import NotificationSummarizer

/// Covers the categories surfaced by the dashboard and the SwiftData round-trip.
final class NotificationCategoryTests: XCTestCase {

    func testSixCategoriesAreExposed() {
        XCTAssertEqual(NotificationCategory.allCases.count, 6)
        XCTAssertEqual(
            NotificationCategory.allCases.map(\.rawValue),
            ["Work", "Social", "Finance", "Security", "Promotional", "Personal"]
        )
    }

    func testRawValuesMatchCaseLabels() {
        XCTAssertEqual(NotificationCategory.work.rawValue, "Work")
        XCTAssertEqual(NotificationCategory(rawValue: "Finance"), .finance)
        XCTAssertNil(NotificationCategory(rawValue: "finance"), "matching is case-sensitive by design")
        XCTAssertNil(NotificationCategory(rawValue: "Unknown"))
    }

    func testIdentifiersAreUnique() {
        let ids = NotificationCategory.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, NotificationCategory.allCases.map(\.rawValue))
    }

    func testEveryCategoryHasASymbolAndRoundTripsThroughCodable() throws {
        for category in NotificationCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty, "\(category.rawValue) needs an SF Symbol")
            let data = try JSONEncoder().encode(category)
            XCTAssertEqual(try JSONDecoder().decode(NotificationCategory.self, from: data), category)
        }
    }

    func testModelPersistsCategoryAsRawValue() {
        let notification = SummarizedNotification(
            originalText: "Your OTP is 9911",
            summary: "$1 charge",
            category: .security
        )
        XCTAssertEqual(notification.categoryRaw, "Security")
        XCTAssertEqual(notification.category, .security)
    }

    func testModelFallsBackToPersonalForUnknownStoredValue() {
        let notification = SummarizedNotification(
            originalText: "text",
            summary: "summary",
            category: .work
        )
        notification.categoryRaw = "SomethingElse"

        XCTAssertEqual(notification.category, .personal)
    }

    func testModelDefaultsToUnreadAndGeneratedID() {
        let notification = SummarizedNotification(
            originalText: "text",
            summary: "summary",
            category: .personal
        )

        XCTAssertFalse(notification.isRead)
        XCTAssertEqual(notification.originalText, "text")
        XCTAssertNotNil(notification.id)
    }
}
