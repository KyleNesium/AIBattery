import Foundation

extension Data {
    /// `memchr`-backed search for the next `\n` at or after `start`.
    ///
    /// `Data.firstIndex(of:)` walks the generic Collection path one byte at a time and
    /// dominated the cold scan of both JSONL readers (Codex tree: 5.8 s → 1.6 s after
    /// switching). Index arithmetic honours slices whose `startIndex` is non-zero.
    func firstNewlineIndex(from start: Data.Index) -> Data.Index? {
        guard start < endIndex else { return nil }
        return withUnsafeBytes { raw -> Data.Index? in
            let offset = start - startIndex
            let length = raw.count - offset
            guard length > 0, let base = raw.baseAddress?.advanced(by: offset),
                  let hit = memchr(base, Int32(UInt8(ascii: "\n")), length) else { return nil }
            return start + (UnsafeRawPointer(hit) - UnsafeRawPointer(base))
        }
    }
}
