import Foundation

/// Account/workspace info extracted from Anthropic responses.
struct APIProfile {
    let organizationId: String?
    let workspaceId: String?
    let workspaceName: String?

    private static func normalizedHeaderMap(_ headers: [AnyHashable: Any]) -> [String: String] {
        var map: [String: String] = [:]
        for (key, value) in headers {
            guard let key = key as? String, let value = value as? String else { continue }
            map[key.lowercased()] = value
        }
        return map
    }

    private static func sanitizedIdentifier(_ raw: String?) -> String? {
        guard let raw,
              !raw.isEmpty,
              raw.count <= 128,
              raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return raw
    }

    private static func sanitizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256 else { return nil }
        return trimmed
    }

    static func parse(headers: [AnyHashable: Any]) -> APIProfile? {
        let normalized = normalizedHeaderMap(headers)
        let orgId = sanitizedIdentifier(normalized["anthropic-organization-id"])
        let workspaceId = sanitizedIdentifier(
            normalized["anthropic-workspace-id"] ?? normalized["anthropic-workspace"]
        )
        let workspaceName = sanitizedName(
            normalized["anthropic-workspace-name"] ?? normalized["x-workspace-name"]
        )

        guard orgId != nil || workspaceId != nil || workspaceName != nil else { return nil }
        return APIProfile(
            organizationId: orgId,
            workspaceId: workspaceId,
            workspaceName: workspaceName
        )
    }

    static func parse(clientData data: Data) -> APIProfile? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parse(clientDataJSON: json)
    }

    private static func parse(clientDataJSON json: Any) -> APIProfile? {
        func normalizedKeys(from dictionary: [String: Any]) -> [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                result[key.lowercased().replacingOccurrences(of: "-", with: "_")] = value
            }
            return result
        }

        func dictionary(_ value: Any?) -> [String: Any]? {
            guard let value = value as? [String: Any] else { return nil }
            return normalizedKeys(from: value)
        }

        func string(_ value: Any?) -> String? {
            value as? String
        }

        func lookup(in json: Any, path: [String]) -> Any? {
            guard !path.isEmpty else { return json }
            guard let dict = dictionary(json), let value = dict[path[0]] else { return nil }
            return lookup(in: value, path: Array(path.dropFirst()))
        }

        func firstValue(in json: Any, paths: [[String]]) -> String? {
            for path in paths {
                if let value = string(lookup(in: json, path: path)) { return value }
            }
            return nil
        }

        let orgId = sanitizedIdentifier(firstValue(in: json, paths: [
            ["organization_id"],
            ["organization", "id"],
            ["org", "id"],
            ["account", "organization_id"],
            ["account", "org_id"],
        ]))

        let workspaceId = sanitizedIdentifier(firstValue(in: json, paths: [
            ["workspace_id"],
            ["workspace", "id"],
            ["account", "workspace_id"],
            ["account", "workspace", "id"],
        ]))

        let workspaceName = sanitizedName(firstValue(in: json, paths: [
            ["workspace_name"],
            ["workspace", "name"],
            ["account", "workspace_name"],
            ["account", "workspace", "name"],
        ]))

        guard orgId != nil || workspaceId != nil || workspaceName != nil else { return nil }
        return APIProfile(
            organizationId: orgId,
            workspaceId: workspaceId,
            workspaceName: workspaceName
        )
    }
}
