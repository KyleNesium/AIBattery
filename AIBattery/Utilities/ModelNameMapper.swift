import Foundation

enum ModelNameMapper {
    static func displayName(for modelId: String) -> String {
        guard !modelId.isEmpty else { return "Unknown" }

        // Strip "claude-" prefix
        var name = modelId
        if name.hasPrefix("claude-") {
            name = String(name.dropFirst(7))
        }

        // Strip trailing date segment (8+ digits like 20250929)
        if let range = name.range(of: #"-\d{8}.*$"#, options: .regularExpression) {
            name = String(name[name.startIndex..<range.lowerBound])
        }

        // If stripping left nothing (e.g., "claude-20250101"), return original ID
        guard !name.isEmpty else { return modelId }

        // Convert "opus-4-6" -> "Opus 4.6", "sonnet-4-5" -> "Sonnet 4.5"
        let parts = name.split(separator: "-")
        guard let family = parts.first else { return modelId }

        let familyName = family.prefix(1).uppercased() + family.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")

        if version.isEmpty {
            return familyName
        }
        return "\(familyName) \(version)"
    }
}
