import Foundation

enum ModelNameMapper {
    /// Pre-compiled regex for stripping trailing date segments (e.g. "-20250929").
    /// Pattern is a compile-time constant — force-try is safe here.
    private static let dateRegex = try! NSRegularExpression(pattern: #"-\d{8}.*$"#)

    static func displayName(for modelId: String) -> String {
        guard !modelId.isEmpty else { return "Unknown" }

        // Strip "claude-" prefix
        var name = modelId
        if name.hasPrefix("claude-") {
            name = String(name.dropFirst(7))
        }

        // Strip trailing date segment (8+ digits like 20250929)
        let nsRange = NSRange(name.startIndex..., in: name)
        if let match = dateRegex.firstMatch(in: name, range: nsRange),
           let range = Range(match.range, in: name) {
            name = String(name[name.startIndex..<range.lowerBound])
        }

        // If stripping left nothing (e.g., "claude-20250101"), return original ID
        guard !name.isEmpty else { return modelId }

        // Convert "opus-4-6" -> "Opus 4.6", "sonnet-4-5" -> "Sonnet 4.5"
        // Handle old format: "3-5-sonnet" -> "Sonnet 3.5", "3-opus" -> "Opus 3"
        let parts = name.split(separator: "-")
        guard let first = parts.first else { return modelId }

        if first.first?.isNumber == true {
            // Old format: version-first, e.g. "3-5-sonnet" or "3-opus"
            let familyIndex = parts.firstIndex { $0.first?.isNumber == false } ?? parts.endIndex
            let versionParts = parts[parts.startIndex..<familyIndex]
            let familyParts = parts[familyIndex...]

            let familyName = familyParts.map { String($0.prefix(1)).uppercased() + $0.dropFirst() }.joined(separator: " ")
            let version = versionParts.joined(separator: ".")

            if familyName.isEmpty { return version.isEmpty ? modelId : version }
            if version.isEmpty { return familyName }
            return "\(familyName) \(version)"
        }

        // New format: family-first, e.g. "opus-4-6"
        let familyName = first.prefix(1).uppercased() + first.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")

        if version.isEmpty {
            return familyName
        }
        return "\(familyName) \(version)"
    }
}
