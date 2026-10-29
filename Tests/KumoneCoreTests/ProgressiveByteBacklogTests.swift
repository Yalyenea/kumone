import Foundation
import Testing
@testable import KumoneCore

@Suite("ProgressiveByteBacklog")
struct ProgressiveByteBacklogTests {
    private func directory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/tests/byte-backlog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func interleavedWritesKeepByteOrderAndReuseDrainedFile() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backlog = try ProgressiveByteBacklog(directory: directory)
        defer { backlog.close() }
        let first = Data(repeating: 1, count: ProgressiveByteBacklog.chunkBytes + 7)
        let second = Data(repeating: 2, count: 19)
        try backlog.append(first)
        #expect(try backlog.readChunk() == first.prefix(ProgressiveByteBacklog.chunkBytes))
        try backlog.append(second)
        #expect(try backlog.readChunk() == Data(repeating: 1, count: 7) + second)
        #expect(backlog.remainingBytes == 0)
        #expect(try backlog.readChunk() == nil)

        // A later burst must start at byte zero after truncation, even though
        // the previous read left the descriptor positioned past the old bytes.
        try backlog.append(second)
        #expect(try backlog.readChunk() == second)
        #expect(backlog.remainingBytes == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func largeBacklogDrainsInBoundedChunks() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backlog = try ProgressiveByteBacklog(directory: directory)
        defer { backlog.close() }
        let chunk = Data(repeating: 0xA5, count: ProgressiveByteBacklog.chunkBytes)
        let chunks = 2048 // 64 MiB waiting on disk; the producer reuses one Data.
        for _ in 0..<chunks { try backlog.append(chunk) }
        #expect(backlog.remainingBytes == UInt64(chunk.count * chunks))
        var count = 0
        while let next = try backlog.readChunk() {
            #expect(next.count <= ProgressiveByteBacklog.chunkBytes)
            #expect(next == chunk)
            count += 1
        }
        #expect(count == chunks)
        #expect(backlog.remainingBytes == 0)
    }

    @Test func cancellationClosesAndDiscardsBacklog() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backlog = try ProgressiveByteBacklog(directory: directory)
        try backlog.append(Data(repeating: 3, count: 1024))
        backlog.close()
        backlog.close()
        #expect(backlog.remainingBytes == 0)
        #expect(throws: ProgressiveByteBacklog.BacklogError.self) { try backlog.readChunk() }
        #expect(throws: ProgressiveByteBacklog.BacklogError.self) { try backlog.append(Data([4])) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func fileCreationFailureIsReported() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: NSError.self) {
            try ProgressiveByteBacklog(directory: directory.appendingPathComponent("missing"))
        }
    }
}
