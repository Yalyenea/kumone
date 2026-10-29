import Darwin
import Foundation

/// Encoded bytes waiting for the decoder. All access stays on the loader's
/// serial queue; only one small read chunk enters memory at a time.
final class ProgressiveByteBacklog {
    static let chunkBytes = 32 * 1024

    enum BacklogError: Error {
        case closed
        case unexpectedEndOfFile
    }

    private var file: FileHandle?
    private var readOffset: UInt64 = 0
    private var writeOffset: UInt64 = 0
    var remainingBytes: UInt64 { writeOffset - readOffset }

    init(directory: URL = FileManager.default.temporaryDirectory) throws {
        var path = Array(directory.appendingPathComponent("kumone-audio-backlog.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&path)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        // The open descriptor owns the bytes. No file can survive a cancelled
        // stream or a process crash, and cache promotion cannot move this FIFO.
        guard unlink(path) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            Darwin.close(descriptor)
            throw error
        }
        file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func append(_ data: Data) throws {
        guard let file else { throw BacklogError.closed }
        guard !data.isEmpty else { return }
        try file.seek(toOffset: writeOffset)
        try file.write(contentsOf: data)
        writeOffset += UInt64(data.count)
    }

    func readChunk() throws -> Data? {
        guard let file else { throw BacklogError.closed }
        guard remainingBytes > 0 else { return nil }
        let count = Int(min(UInt64(Self.chunkBytes), remainingBytes))
        try file.seek(toOffset: readOffset)
        guard let data = try file.read(upToCount: count), !data.isEmpty else {
            throw BacklogError.unexpectedEndOfFile
        }
        readOffset += UInt64(data.count)
        if readOffset == writeOffset {
            // Reuse an empty file without retaining every earlier burst on disk.
            try file.truncate(atOffset: 0)
            readOffset = 0
            writeOffset = 0
        }
        return data
    }

    func close() {
        try? file?.close()
        file = nil
        readOffset = 0
        writeOffset = 0
    }
}
