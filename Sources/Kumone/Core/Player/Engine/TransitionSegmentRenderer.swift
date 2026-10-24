import AVFoundation
import Foundation

/// Renders a scored transition ahead of playback using the same audio graph
/// and automation curves as offline audition.
enum TransitionSegmentRenderer {

    /// How much of the outgoing track the segment duplicates before the out
    /// point, and how much of the incoming track it duplicates after the
    /// overlap has finished settling.
    ///
    /// Both exist for the same reason: the moment a deck is swapped for the
    /// segment (or back) cannot be made sample-exact by a timer, but *can* be
    /// made inaudible by having both sides carry the same audio at the same
    /// level for a moment and crossfading between them. Half a second is long
    /// enough to hide the engine's tick granularity and short enough that the
    /// extra material costs nothing to render.
    ///
    /// **Segments never carry a tempo ramp, by construction.** The head window
    /// is exactly the outgoing source span `[outPoint − handoff, outPoint]`,
    /// and `TransitionAutomation.tempoRamp` anchors every glide to *finish* at
    /// `outPoint − segmentHandoff` — the same instant. So the segment's whole
    /// pre-roll sits in the flat, fully-bent stretch, is rendered at a constant
    /// `outgoingRate`, and is byte-identical to what the deck is playing there.
    static let handoff: TimeInterval = TransitionAutomation.segmentHandoff

    /// Bound the audio buffer and the work a background render may allocate.
    static let maxOverlap: TimeInterval = 30

    struct Request: Sendable {
        var planned: PlannedTransition
        var outgoingURL: URL
        var incomingURL: URL
        /// The trims the two decks are (or will be) loaded at, so the segment
        /// is at exactly the level the decks it replaces would have played.
        var outgoingTrimDB: Double = 0
        var incomingTrimDB: Double = 0
        /// Whether the player will play this segment through a master limiter,
        /// which decides whether the bent-rate headroom pad is baked into it
        /// (`OfflineTransitionRenderer.Options.masterLimiterActive`). The
        /// segment has to agree with the decks either side of the splice, and
        /// this is the only way it can be told which regime they are in.
        var masterLimiterActive = false
        /// Analyses place the score on both tracks' bar grids.
        var outgoingAnalysis: TrackAnalysis?
        /// The incoming track's analysis. Only a `TransitionScore` needs it —
        /// the bar grid the score's non-negative bars are addressed on is the
        /// incoming track's. Without it a score cannot compile and the seam
        /// takes the live blend.
        var incomingAnalysis: TrackAnalysis?
    }

    enum SegmentError: LocalizedError {
        case noOverlap
        case overlapTooLong(TimeInterval)
        case nothingToRender
        case scoreNotCompiled(String?)
        case scoreNotApplied(String?)
        case emptyRender

        var errorDescription: String? {
            switch self {
            case .noOverlap:
                return "a pre-rendered segment needs an overlap; this plan has none"
            case .overlapTooLong(let seconds):
                return String(format: "overlap of %.1fs is longer than the pre-render budget",
                              seconds)
            case .nothingToRender:
                return "this hand-over has no score to render"
            case .scoreNotCompiled(let reason):
                return reason ?? "the score could not be placed on the beat grid"
            case .scoreNotApplied(let reason):
                return reason ?? "the score's whole-mix lanes did not run"
            case .emptyRender:
                return "the pre-render produced no audio"
            }
        }
    }

    /// Render one scored hand-over off the main thread.
    static func render(_ request: Request) throws -> TransitionSegment {
        let planned = request.planned
        guard let signature = TransitionSegment.Signature(plan: planned.plan) else {
            throw SegmentError.noOverlap
        }
        let geometry = TransitionAutomation.Geometry(plan: planned.plan)
        guard geometry.overlapDuration > 0 else { throw SegmentError.noOverlap }
        guard geometry.overlapDuration <= maxOverlap else {
            throw SegmentError.overlapTooLong(geometry.overlapDuration)
        }
        guard planned.style.score != nil else { throw SegmentError.nothingToRender }

        var options = OfflineTransitionRenderer.Options()
        options.preRoll = handoff
        options.postRoll = handoff
        // The head window *is* the ramp's flat tail (see `handoff`), so the
        // renderer must not stretch the pre-roll back over the glide: that
        // would put audio the deck never plays into the identity crossfade.
        options.extendPreRollForTempoRamp = false
        options.outgoingTrimDB = request.outgoingTrimDB
        options.incomingTrimDB = request.incomingTrimDB
        options.masterLimiterActive = request.masterLimiterActive
        options.rideDB = planned.rideDB
        // The two audition-only devices are off: nothing normalizes the live
        // signal path, and the ride's release is handed to the deck instead of
        // being rendered out in full (`Mix.rideDBAtEnd`).
        options.normalizeToLUFS = nil
        options.stretchPostRollForRideRelease = false

        // Refuse an unplaceable score before rendering any audio.
        if let score = planned.style.score {
            guard let outgoingAnalysis = request.outgoingAnalysis,
                  let incomingAnalysis = request.incomingAnalysis else {
                throw SegmentError.scoreNotCompiled(
                    "乐谱要按两侧的小节网格落点，这次转场手里没有分析。")
            }
            let compiled = ScoreCompiler.compile(
                score, planned: planned,
                outgoing: outgoingAnalysis, incoming: incomingAnalysis,
                outgoingURL: request.outgoingURL)
            guard let lanes = compiled.lanes else {
                throw SegmentError.scoreNotCompiled(compiled.refusalReason)
            }
            options.mixLanes = lanes
        }

        let mix = try OfflineTransitionRenderer.renderMix(
            planned, outgoing: request.outgoingURL, incoming: request.incomingURL,
            options: options)
        guard mix.lanesApplied != nil else {
            throw SegmentError.scoreNotApplied(mix.scoreFallbackReason)
        }
        guard let buffer = makeBuffer(mix) else { throw SegmentError.emptyRender }

        let duration = Double(buffer.frameLength) / mix.sampleRate
        // The engine's own midpoint rule, evaluated on the rendered timeline:
        // the overlap starts one handoff window in.
        let midpoint = mix.overlapStart + midpointOffset(planned: planned, geometry: geometry)
        return TransitionSegment(
            buffer: buffer, signature: signature, duration: duration,
            outgoingStart: mix.outgoing.first?.source ?? 0,
            handoffIn: mix.overlapStart,
            // The head window on the *song's* clock: the render started the
            // outgoing deck here and pumped until it reached the out point.
            handoffInSource: signature.outPoint - (mix.outgoing.first?.source ?? 0),
            handoffOut: handoff,
            midpointOffset: min(midpoint, duration),
            incomingRideDB: mix.rideDBAtEnd,
            outgoing: mix.outgoing, incoming: mix.incoming)
    }

    /// Seconds into the *overlap* where the audible hand-over lands — the same
    /// rule `TransitionAutomation.frame` latches `midpointReached` on.
    static func midpointOffset(planned: PlannedTransition,
                               geometry: TransitionAutomation.Geometry) -> TimeInterval {
        guard case .beatMatched(let p) = planned.plan else {
            return geometry.overlapDuration * 0.5
        }
        return planned.style.stagedEQ
            ? geometry.swapOffset
            : min(max(p.bassSwapOffset, 0.8), geometry.overlapDuration)
    }

    private static func makeBuffer(_ mix: OfflineTransitionRenderer.Mix) -> AVAudioPCMBuffer? {
        let format = DeckChain.format
        guard let frames = mix.channels.first?.count, frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frames)),
              let data = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(format.channelCount) {
            let source = mix.channels[min(channel, mix.channels.count - 1)]
            source.withUnsafeBufferPointer {
                data[channel].update(from: $0.baseAddress!, count: min(frames, source.count))
            }
        }
        return buffer
    }
}
