import Foundation
import Testing
@testable import KumoneCore

@Suite("Audio cache tests")
struct AudioCacheTests {
    @Test func cacheSizeSettingStaysWithinTheSupportedSteps() async {
        let normalizedValues = await MainActor.run {
            (
                SettingsManager.normalizedAudioCacheSizeMB(20),
                SettingsManager.normalizedAudioCacheSizeMB(550),
                SettingsManager.normalizedAudioCacheSizeMB(25_000)
            )
        }
        #expect(normalizedValues.0 == 100)
        #expect(normalizedValues.1 == 600)
        #expect(normalizedValues.2 == 10_000)
    }

    @Test func exactQualityHitRestoresMetadata() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await write(
            trackID: 1,
            requestedQuality: "lossless",
            servedQuality: "exhigh",
            source: .netease,
            into: cache
        )

        let entry = try await cache.entry(
            for: 1,
            requestedQuality: "lossless"
        )

        #expect(entry?.metadata.servedQuality == "exhigh")
        #expect(entry?.metadata.source == .netease)
        #expect(try await cache.entry(
            for: 1,
            requestedQuality: "standard"
        ) == nil)
    }

    @Test func cacheUsageDeletesPartialFilesLeftByAnEarlierRun() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let partialDirectory = directory.appendingPathComponent("partial", isDirectory: true)
        try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
        let staleFile = partialDirectory.appendingPathComponent("interrupted.part")
        try Data([0x01]).write(to: staleFile)

        _ = try await cache.usage()

        #expect(!FileManager.default.fileExists(atPath: staleFile.path))
    }

    @Test func cacheUsageRecoversInvalidMetadataAndOrphanedFiles() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalidMetadata = directory.appendingPathComponent("7.json")
        let orphanedFile = directory.appendingPathComponent("7-interrupted.mp3")
        try Data("invalid".utf8).write(to: invalidMetadata)
        try Data([0x07]).write(to: orphanedFile)

        let usage = try await cache.usage()

        #expect(usage == .zero)
        #expect(!FileManager.default.fileExists(atPath: invalidMetadata.path))
        #expect(!FileManager.default.fileExists(atPath: orphanedFile.path))
    }

    @Test func releasingTheLastLeaseEnforcesTheLatestCacheLimit() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await write(
            trackID: 3,
            requestedQuality: "exhigh",
            servedQuality: "exhigh",
            source: .netease,
            into: cache
        )
        try await write(
            trackID: 4,
            requestedQuality: "exhigh",
            servedQuality: "exhigh",
            source: .netease,
            into: cache
        )
        let playingEntry = try #require(await cache.entry(
            for: 3,
            requestedQuality: "exhigh"
        ))
        let lease = await cache.retain(playingEntry)

        try await cache.enforce(maximumSizeMB: 0)

        #expect(try await cache.fallbackEntry(for: 3) != nil)
        #expect(try await cache.fallbackEntry(for: 4) == nil)

        try await cache.release(lease)

        #expect(try await cache.fallbackEntry(for: 3) == nil)
    }

    @Test func completingAWriteUsesTheCurrentCacheLimit() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await cache.enforce(maximumSizeMB: 500)
        let session = try await cache.beginWrite(
            trackID: 5,
            requestedQuality: "exhigh",
            servedQuality: "exhigh",
            source: .netease,
            fileExtension: "mp3",
            maximumSizeMB: 500
        )
        try Data(repeating: 0x05, count: 1_024).write(to: session.partialFileURL)

        try await cache.enforce(maximumSizeMB: 100)
        let result = try await cache.commitAndRetain(
            session,
            byteCount: 150_000_000,
            contentType: "audio/mpeg"
        )

        let wasRejected: Bool
        switch result {
        case .rejectedForCurrentLimit:
            wasRejected = true
        case .retained, .deferredDiscard:
            wasRejected = false
        }
        #expect(wasRejected)
        #expect(FileManager.default.fileExists(atPath: session.partialFileURL.path))
        #expect(try await cache.fallbackEntry(for: 5) == nil)

        try await cache.discard(session)

        #expect(!FileManager.default.fileExists(atPath: session.partialFileURL.path))
    }

    @Test func writeSessionAdoptsConfiguredLimitAboveTheDefault() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try await cache.beginWrite(
            trackID: 8,
            requestedQuality: "hires",
            servedQuality: "hires",
            source: .netease,
            fileExtension: "flac",
            maximumSizeMB: 1_000
        )
        let byteCount: Int64 = 600_000_000
        let fileHandle = try FileHandle(forWritingTo: session.partialFileURL)
        try fileHandle.truncate(atOffset: UInt64(byteCount))
        try fileHandle.close()

        let result = try await cache.commitAndRetain(
            session,
            byteCount: byteCount,
            contentType: "audio/flac"
        )

        switch result {
        case .retained(_, let leaseID):
            try await cache.release(leaseID)
        case .deferredDiscard, .rejectedForCurrentLimit:
            Issue.record("The write should use its configured 1 GB limit.")
        }
    }

    @Test func clearingDuringAWriteDefersTemporaryFileRemoval() async throws {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try await cache.beginWrite(
            trackID: 6,
            requestedQuality: "exhigh",
            servedQuality: "exhigh",
            source: .netease,
            fileExtension: "mp3",
            maximumSizeMB: 500
        )
        try Data(repeating: 0x06, count: 1_024).write(to: session.partialFileURL)

        try await cache.clear()
        let result = try await cache.commitAndRetain(
            session,
            byteCount: 1_024,
            contentType: "audio/mpeg"
        )

        let wasDeferred: Bool
        switch result {
        case .deferredDiscard:
            wasDeferred = true
        case .retained, .rejectedForCurrentLimit:
            wasDeferred = false
        }
        #expect(wasDeferred)
        #expect(FileManager.default.fileExists(atPath: session.partialFileURL.path))

        try await cache.discard(session)

        #expect(!FileManager.default.fileExists(atPath: session.partialFileURL.path))
    }

    @Test func prefetchValidatesAudioTypesAndCacheSize() {
        #expect(QueuePrefetcher.resourceContentType(for: "mp3") == "public.mp3")
        #expect(QueuePrefetcher.resourceContentType(for: "jpg") == nil)
        #expect(QueuePrefetcher.canCache(contentLength: 100_000_000, maximumSizeMB: 100))
        #expect(!QueuePrefetcher.canCache(contentLength: 100_000_001, maximumSizeMB: 100))
    }

    private func makeCache() -> (AudioCache, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioCacheTests-\(UUID().uuidString)", isDirectory: true)
        return (AudioCache(cacheDirectory: directory), directory)
    }

    private func write(
        trackID: Int,
        requestedQuality: String,
        servedQuality: String?,
        source: AudioCacheSource,
        into cache: AudioCache
    ) async throws {
        let session = try await cache.beginWrite(
            trackID: trackID,
            requestedQuality: requestedQuality,
            servedQuality: servedQuality,
            source: source,
            fileExtension: "mp3",
            maximumSizeMB: AudioCache.defaultMaximumSizeMB
        )
        let data = Data(repeating: UInt8(trackID), count: 1_024)
        try data.write(to: session.partialFileURL)
        let result = try await cache.commitAndRetain(
            session,
            byteCount: Int64(data.count),
            contentType: "audio/mpeg"
        )
        switch result {
        case .retained(_, let leaseID):
            try await cache.release(leaseID)
        case .deferredDiscard:
            throw AudioCacheWriteError.deferredDiscard
        case .rejectedForCurrentLimit:
            throw AudioCacheWriteError.rejectedForCurrentLimit
        }
    }
}

private enum AudioCacheWriteError: Error {
    case deferredDiscard
    case rejectedForCurrentLimit
}
