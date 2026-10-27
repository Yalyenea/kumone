import os

/// Low-frequency playback lifecycle events, never called from a render callback.
enum PlaybackJournal {
    private static let log = Logger(subsystem: "im.missuo.Kumone", category: "playback")

    static func note(_ message: String) {
        log.log("\(message, privacy: .public)")
    }
}
