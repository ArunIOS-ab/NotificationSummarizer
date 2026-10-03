import SwiftUI

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

    /// Distinct hue per category so the badge carries meaning without reading its label.
    var tint: Color {
        switch self {
        case .work: Color(red: 0.20, green: 0.44, blue: 0.92)
        case .social: Color(red: 0.13, green: 0.62, blue: 0.42)
        case .finance: Color(red: 0.10, green: 0.55, blue: 0.36)
        case .security: Color(red: 0.86, green: 0.27, blue: 0.24)
        case .promotional: Color(red: 0.85, green: 0.49, blue: 0.09)
        case .personal: Color(red: 0.53, green: 0.34, blue: 0.83)
        }
    }
}
