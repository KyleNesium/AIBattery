import Foundation

/// Reads a file in fixed-size chunks through **one** reused buffer.
///
/// `FileHandle.read(upToCount:)` allocates a fresh `Data` for every chunk — ~331 of them
/// per 21 MB session log — and the allocator keeps the freed pages dirty. Measured on
/// the real tree: ~479 MB launch footprint peak (Claude-only; both providers would be
/// roughly double). An isolation test on one 21 MB file put the shipping loop at +26 MB
/// retained against +5.2 MB and flat for a reused buffer, at identical wall time — so
/// this is a memory fix, not a speed one.
///
/// Reads go through `read(2)` on the handle's descriptor rather than `FileHandle`, which
/// is what makes a single buffer possible. `EINTR` is retried; any other error ends the
/// read, exactly like the `try?` it replaces.
struct ChunkedFileReader {
    static let defaultBufferSize = 64 * 1_024

    private let descriptor: Int32
    private var buffer: [UInt8]

    init(handle: FileHandle, bufferSize: Int = ChunkedFileReader.defaultBufferSize) {
        descriptor = handle.fileDescriptor
        buffer = [UInt8](repeating: 0, count: max(1, bufferSize))
    }

    /// Append the next chunk to `sink`.
    /// - Returns: `false` at end of file, or on a read error.
    mutating func readChunk(into sink: inout Data) -> Bool {
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { raw in
                read(descriptor, raw.baseAddress, raw.count)
            }
            if bytesRead > 0 {
                sink.append(contentsOf: buffer[0..<bytesRead])
                return true
            }
            // 0 is EOF; EINTR means the read was interrupted before any byte, so retry.
            if bytesRead == 0 {
                return false
            }
            if errno == EINTR {
                continue
            }
            return false
        }
    }
}
