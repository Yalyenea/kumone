import AVFoundation
import Foundation

/// Feeds a local audio file whose format differs from the engine's fixed
/// graph format (Hi-Res sample rates, mono files): reads the file in chunks
/// on its own queue, converts to the graph format, and delivers ~0.5s PCM
/// buffers to the engine queue — the same shape as ProgressiveLoader, minus
/// the network.
///
/// The graph never reconfigures for these files (reconnecting a running
/// AVAudioEngine graph while it renders can throw NSException); conversion
/// happens here before buffers reach the player node.
///
/// Threading: all file I/O and conversion on `workQueue`; `onBuffer`/
/// `onEnded` fire on `callbackQueue` (the engine queue). Public methods may
/// be called from the engine queue.
final class FileFeeder: @unchecked Sendable {

    /// Converted PCM in roughly 0.5s chunks, in file order.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// The whole file has been delivered (fires after the last onBuffer).
    var onEnded: (() -> Void)?

    /// Duration in file time (unaffected by the conversion).
    let duration: TimeInterval

    /// Reopened on seek so file reads stay on the work queue.
    private let fileURL: URL
    private let outputFormat: AVAudioFormat
    private let callbackQueue: DispatchQueue
    private let workQueue = DispatchQueue(label: "app.kumone.file-feeder", qos: .userInitiated)

    // workQueue state
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var cancelled = false
    private var ended = false
    /// Buffers delivered but not yet reported played; capped for memory.
    private var inFlight = 0
    private let maxInFlight = 8
    private var generation = 0

    // Reject callbacks queued before the latest seek or cancellation.
    private let generationLock = NSLock()
    private var callbackGeneration = 0
    private var liveGeneration: Int {
        get { generationLock.lock(); defer { generationLock.unlock() }; return callbackGeneration }
        set { generationLock.lock(); callbackGeneration = newValue; generationLock.unlock() }
    }

    /// Deliver on the callback queue, unless the run that produced this has
    /// since been superseded.
    private func deliver(generation: Int, _ body: @escaping () -> Void) {
        callbackQueue.async { [weak self] in
            guard let self, self.liveGeneration == generation else { return }
            body()
        }
    }

    init(file: AVAudioFile, output: AVAudioFormat, queue: DispatchQueue) {
        self.fileURL = file.url
        self.outputFormat = output
        self.callbackQueue = queue
        self.duration = Double(file.length) / file.processingFormat.sampleRate
    }

    /// (Re)start delivery from `seconds` in file time. Any earlier run's
    /// pending chunks are discarded.
    func start(from seconds: TimeInterval) {
        workQueue.async {
            self.generation += 1
            self.liveGeneration = self.generation
            let generation = self.generation
            self.ended = false
            self.inFlight = 0
            guard let file = try? AVAudioFile(forReading: self.fileURL) else {
                self.ended = true
                let cb = self.onEnded
                self.deliver(generation: generation) { cb?() }
                return
            }
            let frame = AVAudioFramePosition((max(0, seconds) * file.processingFormat.sampleRate).rounded())
            file.framePosition = min(frame, file.length)
            self.file = file
            self.converter = AVAudioConverter(from: file.processingFormat, to: self.outputFormat)
            self.fillOnQueue(generation: generation)
        }
    }

    /// The engine played one delivered buffer; keep the window full.
    func bufferPlayed() {
        workQueue.async {
            self.inFlight = max(0, self.inFlight - 1)
            self.fillOnQueue(generation: self.generation)
        }
    }

    func cancel() {
        workQueue.async {
            self.cancelled = true
            self.generation += 1
            self.liveGeneration = self.generation
            self.file = nil
            self.converter = nil
        }
    }

    // MARK: - workQueue

    private func fillOnQueue(generation: Int) {
        guard !cancelled, !ended, generation == self.generation,
              let file, let converter else { return }
        let srcRate = file.processingFormat.sampleRate
        let chunkFrames = AVAudioFrameCount(srcRate / 2) // ~0.5s of source

        while inFlight < maxInFlight {
            guard file.framePosition < file.length else {
                // Rate conversion buffers internally; drain the tail.
                while true {
                    guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8192)
                    else { break }
                    var error: NSError?
                    let status = converter.convert(to: out, error: &error) { _, st in
                        st.pointee = .endOfStream
                        return nil
                    }
                    if out.frameLength > 0 {
                        let cb = onBuffer
                        deliver(generation: generation) { cb?(out) }
                    }
                    if status != .haveData { break }
                }
                ended = true
                let cb = onEnded
                deliver(generation: generation) { cb?() }
                return
            }
            guard let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: chunkFrames) else { return }
            do {
                try file.read(into: src, frameCount: chunkFrames)
            } catch {
                ended = true
                let cb = onEnded
                deliver(generation: generation) { cb?() }
                return
            }
            guard src.frameLength > 0 else { continue }

            let outCapacity = AVAudioFrameCount(
                (Double(src.frameLength) * outputFormat.sampleRate / srcRate).rounded(.up) + 64)
            guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                             frameCapacity: outCapacity) else { return }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, st in
                if fed {
                    st.pointee = .noDataNow
                    return nil
                }
                fed = true
                st.pointee = .haveData
                return src
            }
            guard status != .error else {
                ended = true
                let cb = onEnded
                deliver(generation: generation) { cb?() }
                return
            }
            guard out.frameLength > 0 else { continue }
            inFlight += 1
            let cb = onBuffer
            deliver(generation: generation) { cb?(out) }
        }
    }
}
