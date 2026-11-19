import Foundation

enum ModelNameMapper {
    /// `nonisolated(unsafe)` is the right call here: every read/write is guarded by
    /// `lock` below, so the data is concurrency-safe even though Swift can't see it.
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func displayName(for modelId: String) -> String {
        lock.withLock {
            if let cached = cache[modelId] {
                return cached
            }
            let result = computeDisplayName(for: modelId)
            cache[modelId] = result
            return result
        }
    }

    /// Claude model families, as they appear in a lowercased display name.
    static let claudeFamilies = ["fable", "mythos", "opus", "sonnet", "haiku"]

    /// The family and version of a Claude model id, read from its display name:
    /// "claude-fable-5-2" → ("fable", [5, 2]), "claude-3-5-sonnet-20241022" → ("sonnet", [3, 5]),
    /// "opus" → ("opus", []). A Bedrock id resolves the same way
    /// ("global.anthropic.claude-fable-5-2" displays as "Global.anthropic.claude fable.5.2").
    /// nil for an id of no known family.
    static func claudeFamilyAndVersion(of modelId: String) -> (family: String, version: [Int])? {
        let name = displayName(for: modelId).lowercased()
        guard let family = claudeFamilies.first(where: { name.contains($0) }),
              let familyEnd = name.range(of: family)?.upperBound
        else {
            return nil
        }
        return (family, versionNumbers(in: name[familyEnd...]))
    }

    /// The first dotted number in `text`: " 4.6[1m]" → [4, 6], ".5.2" → [5, 2], "" → [].
    static func versionNumbers(in text: some StringProtocol) -> [Int] {
        let isDigit: (Character) -> Bool = { ("0"..."9").contains($0) }
        return text.drop { !isDigit($0) }.prefix { isDigit($0) || $0 == "." }
            .split(separator: ".").compactMap { Int($0) }
    }

    private static func computeDisplayName(for modelId: String) -> String {
        guard !modelId.isEmpty else { return "Unknown" }

        // OpenAI / Codex: "gpt-5.4" → "GPT-5.4", "gpt-5.6-sol" → "GPT-5.6 Sol",
        // "gpt-5-mini" → "GPT-5 Mini". Version token kept verbatim; suffixes capitalised.
        if modelId.hasPrefix("gpt-") {
            let parts = modelId.dropFirst(4).split(separator: "-")
            guard let version = parts.first else { return modelId }
            let suffixes = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return (["GPT-\(version)"] + suffixes).joined(separator: " ")
        }

        // Strip "claude-" prefix
        var name = modelId
        if name.hasPrefix("claude-") {
            name = String(name.dropFirst(7))
        }

        // Strip trailing date segment: first "-" followed by 8+ consecutive digits, and everything after.
        // Matches the old regex behavior of `-\d{8}.*$`.
        var searchFrom = name.startIndex
        while searchFrom < name.endIndex {
            guard let dashIdx = name[searchFrom...].firstIndex(of: "-") else { break }
            let afterDash = name.index(after: dashIdx)
            guard afterDash < name.endIndex else { break }
            // Count consecutive digits from afterDash
            var digitEnd = afterDash
            while digitEnd < name.endIndex, name[digitEnd].isNumber {
                digitEnd = name.index(after: digitEnd)
            }
            if name.distance(from: afterDash, to: digitEnd) >= 8 {
                name = String(name[name.startIndex..<dashIdx])
                break
            }
            searchFrom = name.index(after: dashIdx)
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

            if familyName.isEmpty {
                return version.isEmpty ? modelId : version
            }
            if version.isEmpty {
                return familyName
            }
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
