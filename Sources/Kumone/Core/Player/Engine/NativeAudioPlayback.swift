import AVFoundation
import Foundation

/// Serialized on PlaybackEngine's queue. AVPlayer keeps high-resolution and
/// spatial sources out of the stereo AutoMix graph and lets macOS render the
/// source for the selected output device.
final class NativeAudioPlayback: @unchecked Sendable {
    private let player: AVPlayer
    private let item: AVPlayerItem
    private let queue: DispatchQueue
    private let deck: Deck
    private let onEvent: @Sendable (PlaybackEngineEvent) -> Void
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var wantsPlayback = false
    private var stopped = false
    private var seeking = false
    private var seekGeneration = 0
    private var seekPosition: Double = 0
    private let expectedDuration: Double

    init(url: URL, duration: Double, deck: Deck, volume: Float, outputDeviceUID: String?,
         queue: DispatchQueue, onEvent: @escaping @Sendable (PlaybackEngineEvent) -> Void) {
        self.queue = queue
        self.deck = deck
        self.onEvent = onEvent
        expectedDuration = duration
        item = AVPlayerItem(url: url)
        item.allowedAudioSpatializationFormats = .multichannel
        player = AVPlayer(playerItem: item)
        player.volume = volume
        player.audioOutputDeviceUniqueID = outputDeviceUID
        observations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let error = item.error ?? URLError(.cannotDecodeContentData)
                self?.deliver(.streamFailed(deck, error))
            },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate: self?.deliver(.streamStalled(deck))
                case .playing: self?.deliver(.streamResumed(deck))
                default: break
                }
            }
        ]
        let center = NotificationCenter.default
        notifications = [
            center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: nil) { [weak self] _ in
                self?.deliver(.deckFinished(deck))
            },
            center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    ?? URLError(.cannotDecodeContentData)
                self?.deliver(.streamFailed(deck, error))
            }
        ]
    }

    private func deliver(_ event: PlaybackEngineEvent) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.onEvent(event)
        }
    }

    var position: Double {
        if seeking { return seekPosition }
        let value = player.currentTime().seconds
        return value.isFinite ? value : seekPosition
    }

    var duration: Double {
        let value = item.duration.seconds
        return value.isFinite && value > 0 ? value : expectedDuration
    }

    func play(from seconds: Double) {
        wantsPlayback = true
        if abs(position - seconds) > 0.05 { seek(to: seconds) }
        else if !seeking { player.play() }
    }

    func seek(to seconds: Double) {
        seekGeneration += 1
        let generation = seekGeneration
        seeking = true
        seekPosition = max(0, seconds)
        player.pause()
        player.seek(to: CMTime(seconds: seekPosition, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            guard let self else { return }
            self.queue.async {
                guard !self.stopped, self.seekGeneration == generation else { return }
                self.seeking = false
                if completed && self.wantsPlayback { self.player.play() }
            }
        }
    }

    func pause() { wantsPlayback = false; player.pause() }
    func resume() { wantsPlayback = true; if !seeking { player.play() } }
    func setVolume(_ value: Float) { player.volume = value }
    func setOutputDevice(uid: String?) { player.audioOutputDeviceUniqueID = uid }

    func stop() {
        stopped = true
        wantsPlayback = false
        seekGeneration += 1
        player.pause()
        observations.removeAll()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    deinit { notifications.forEach { NotificationCenter.default.removeObserver($0) } }
}
