import Foundation
import os

@MainActor
final class StatsCacheReader {
    static let shared = StatsCacheReader()

    private static let jsonDecoder = JSONDecoder()
    /// Maximum file size to read (10 MB). stats-cache.json is typically a few KB;
    /// anything larger suggests a symlink to a large file or a runaway writer.
    static let maxFileSize: UInt64 = 10_000_000
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ClaudePaths.statsCache
    }

    /// Cached decode result — avoids re-reading and decoding on every refresh.
    private var cached: StatsCache?
    private var cachedModDate: Date?
    private var cachedFileSize: UInt64?

    /// Last known modification date of stats-cache.json. Used by UsageAggregator
    /// to detect whether re-aggregation is needed.
    var lastModificationDate: Date? { cachedModDate }

    /// Called by FileWatcher when the stats-cache file changes.
    func invalidate() {
        cached = nil
        cachedModDate = nil
        cachedFileSize = nil
    }

    func read() -> StatsCache? {
        let path = fileURL.path

        // Single stat() call — replaces fileExists + attributesOfItem double stat
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            AppLogger.files.info("StatsCacheReader: stats-cache.json not found")
            return nil
        }
        let modDate = attrs[.modificationDate] as? Date
        let fileSize = attrs[.size] as? UInt64

        // File type guard — reject pipes, devices, etc.
        guard attrs[.type] as? FileAttributeType == .typeRegular else {
            AppLogger.files.warning("StatsCacheReader: not a regular file, skipping")
            return nil
        }

        // Symlink boundary check — reject files resolving outside ~/.claude/
        let resolvedPath = fileURL.resolvingSymlinksInPath().path
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude").resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix(claudeDir) else {
            AppLogger.files.warning("StatsCacheReader: file resolves outside ~/.claude/, skipping")
            return nil
        }

        // Size guard
        if let fileSize, fileSize > Self.maxFileSize {
            AppLogger.files.warning("StatsCacheReader: file too large (\(fileSize) bytes), skipping")
            return nil
        }

        // Cache hit — skip re-decode when file unchanged
        if let c = cached, let modDate, let fileSize,
           modDate == cachedModDate, fileSize == cachedFileSize {
            return c
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let result = try Self.jsonDecoder.decode(StatsCache.self, from: data)
            cached = result
            cachedModDate = modDate
            cachedFileSize = fileSize
            return result
        } catch {
            AppLogger.files.error("StatsCacheReader: error reading stats cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
