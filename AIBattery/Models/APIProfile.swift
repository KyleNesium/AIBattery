import Foundation

/// Organization info extracted from the Messages API response headers.
struct APIProfile {
    let organizationId: String?

    static func parse(headers: [AnyHashable: Any]) -> APIProfile? {
        guard let orgId = headers["anthropic-organization-id"] as? String else { return nil }
        return APIProfile(organizationId: orgId)
    }
}
