import Foundation

/// Modification date without bridging a full ~15-key NSDictionary.
///
/// `FileManager.attributesOfItem` was measured at roughly nine times the cost of
/// `resourceValues` (71.7 ms vs 7.8 ms across 1722 files), and the session-log readers
/// stat every project directory on every discovery pass — which runs on every
/// invalidation while a session is actively writing.
///
/// NSURL caches resource values on the URL instance, so a reused URL keeps reporting the
/// pre-write date. The cache is dropped before each read; without that a changed file
/// would keep its old fingerprint and never be re-parsed.
enum FileStat {
    static func modificationDate(ofPath path: String) -> Date? {
        modificationDate(of: URL(fileURLWithPath: path))
    }

    static func modificationDate(of url: URL) -> Date? {
        var url = url
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
