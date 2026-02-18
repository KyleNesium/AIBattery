import Foundation

/// Organization info extracted from the Messages API response headers.
struct APIProfile {
    let organizationId: String?
    let organizationName: String?

    static func parse(headers: [AnyHashable: Any]) -> APIProfile? {
        let orgId = headers["anthropic-organization-id"] as? String
        let orgName = headers["x-organization-name"] as? String
        guard orgId != nil || orgName != nil else { return nil }
        return APIProfile(organizationId: orgId, organizationName: orgName)
    }
}
