import Foundation

/// Organization info extracted from the Messages API response headers.
struct APIProfile {
    let organizationId: String?

    static func parse(headers: [AnyHashable: Any]) -> APIProfile? {
        guard let orgId = headers["anthropic-organization-id"] as? String,
              !orgId.isEmpty,
              orgId.count <= 128,
              orgId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return APIProfile(organizationId: orgId)
    }
}
