import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ChunkedFileReader")
struct ChunkedFileReaderTests {
    private func withTempFile(_ contents: Data, _ body: (FileHandle) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunked-\(UUID().uuidString).bin")
        try contents.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try body(handle)
    }

    @Test func readsTheWholeFileAcrossChunkBoundaries() throws {
        let payload = Data((0..<10_000).map { UInt8($0 % 251) })
        try withTempFile(payload) { handle in
            var reader = ChunkedFileReader(handle: handle, bufferSize: 512)
            var sink = Data()
            var chunks = 0
            while reader.readChunk(into: &sink) {
                chunks += 1
            }
            #expect(sink == payload)
            #expect(chunks >= 10_000 / 512)
        }
    }

    @Test func appendsToExistingContentAndReportsEOF() throws {
        try withTempFile(Data("world".utf8)) { handle in
            var reader = ChunkedFileReader(handle: handle, bufferSize: 64)
            var sink = Data("hello ".utf8)
            let read = reader.readChunk(into: &sink)
            #expect(read)
            #expect(String(data: sink, encoding: .utf8) == "hello world")
            // Second call is at EOF and must not touch the sink.
            let atEOF = reader.readChunk(into: &sink)
            #expect(!atEOF)
            #expect(String(data: sink, encoding: .utf8) == "hello world")
        }
    }

    @Test func emptyFileReportsEOFImmediately() throws {
        try withTempFile(Data()) { handle in
            var reader = ChunkedFileReader(handle: handle)
            var sink = Data()
            let read = reader.readChunk(into: &sink)
            #expect(!read)
            #expect(sink.isEmpty)
        }
    }
}
