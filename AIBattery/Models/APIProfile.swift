import Foundation

/// Organization info extracted from the Messages API response headers.
struct APIProfile {
    let organizationId: String?

    static func parse(headers: [AnyHashable: Any]) -> APIProfile? {
        // Case-insensitive lookup — HTTPURLResponse bridging can lose case-insensitivity.
        let orgId: String? = headers.lazy
            .compactMap { key, value -> String? in
                guard let k = key as? String,
                      k.lowercased() == "anthropic-organization-id",
                      let v = value as? String else { return nil }
                return v
            }
            .first
        guard let orgId,
              !orgId.isEmpty,
              orgId.count <= 128,
              orgId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return APIProfile(organizationId: orgId)
    }
}
