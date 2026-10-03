import Foundation

enum NotificationCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case work = "Work"
    case social = "Social"
    case finance = "Finance"
    case security = "Security"
    case promotional = "Promotional"
    case personal = "Personal"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .work: "briefcase.fill"
        case .social: "message.fill"
        case .finance: "creditcard.fill"
        case .security: "lock.shield.fill"
        case .promotional: "tag.fill"
        case .personal: "person.fill"
        }
    }
}
