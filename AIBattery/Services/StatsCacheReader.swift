import Foundation
import os

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

    /// Called by FileWatcher when the stats-cache file changes.
    func invalidate() {
        cached = nil
        cachedModDate = nil
        cachedFileSize = nil
    }

    func read() -> StatsCache? {
        let fm = FileManager.default
        let path = fileURL.path
        guard fm.fileExists(atPath: path) else {
            AppLogger.files.info("StatsCacheReader: stats-cache.json not found")
            return nil
        }

        // Check mod date + size to skip re-decode when file unchanged
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date,
           let fileSize = attrs[.size] as? UInt64 {
            guard fileSize <= Self.maxFileSize else {
                AppLogger.files.warning("StatsCacheReader: file too large (\(fileSize) bytes), skipping")
                return nil
            }
            if let c = cached, modDate == cachedModDate, fileSize == cachedFileSize {
                return c
            }
            // File changed — decode fresh
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

        // Fallback: can't stat — check size explicitly before reading
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > Self.maxFileSize {
            AppLogger.files.warning("StatsCacheReader: file too large (\(fileSize) bytes), skipping")
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let result = try Self.jsonDecoder.decode(StatsCache.self, from: data)
            cached = result
            return result
        } catch {
            AppLogger.files.error("StatsCacheReader: error reading stats cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
