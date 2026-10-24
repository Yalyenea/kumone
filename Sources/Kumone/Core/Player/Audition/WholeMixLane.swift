import AVFoundation
import Foundation

/// A gain curve on one side's whole mix, in **overlap-relative seconds**.
///
/// Between breakpoints the gain is a raised cosine in *amplitude* rather than
/// linear in dB: a cut edge runs from unity to −60 dB in 8 ms, and dB-linear
/// over that span spends most of it inaudible while the last millisecond does
/// all the work — which is a click with extra steps. The raised cosine is the
/// physical shape of a DJ's fader hand, which is what an edge is imitating.
///
/// An **empty lane is pass-through**, and so is a lane of nothing but 0 dB.
struct WholeMixLane: Sendable, Equatable {

    struct Point: Sendable, Equatable {
        /// Seconds from the start of the overlap.
        var t: TimeInterval
        var gainDB: Float

        init(t: TimeInterval, gainDB: Float) {
            self.t = t
            self.gainDB = gainDB
        }
    }

    var points: [Point]

    init(_ points: [Point] = []) { self.points = points }

    /// The cut floor keeps the edge quiet without stepping the signal.
    static let minGainDB: Float = -60

    /// How long a cut edge takes. The predev's 5–10 ms: fast enough that a
    /// listener hears an event and not a fade, slow enough that the waveform
    /// is not stepped (0 ms is a click, not a cut).
    static let cutEdgeSeconds: TimeInterval = 0.008

    var isPassThrough: Bool { points.allSatisfy { $0.gainDB == 0 } }

    /// Linear gain at `t`, clamped to the endpoints outside the range.
    func gain(at t: TimeInterval) -> Float {
        guard let first = points.first, let last = points.last else { return 1 }
        if t <= first.t { return Self.linear(first.gainDB) }
        if t >= last.t { return Self.linear(last.gainDB) }
        for i in 1..<points.count where points[i].t >= t {
            return Self.interpolate(points[i - 1], points[i], at: t)
        }
        return Self.linear(last.gainDB)
    }

    static func linear(_ db: Float) -> Float { LoudnessCompensation.linearGain(db) }

    /// Raised cosine in amplitude between two breakpoints.
    static func interpolate(_ a: Point, _ b: Point, at t: TimeInterval) -> Float {
        let span = b.t - a.t
        let v0 = linear(a.gainDB), v1 = linear(b.gainDB)
        guard span > 1e-12 else { return v1 }
        let u = Swift.min(1, Swift.max(0, (t - a.t) / span))
        let s = Float(0.5 - 0.5 * cos(.pi * u))
        return v0 + (v1 - v0) * s
    }
}

/// A beat-synced delay throw on the outgoing deck, as the compiler leaves it
/// for the renderer.
///
/// This is `.echoOut`'s move with a different ending: the delay is engaged at
/// the last lyric line end before the seam, and what stops the outgoing track
/// is the whole-mix lane's cut rather than a fade. Because the lane is applied
/// to the *source buffer*, upstream of the deck's delay unit, the cut takes the
/// dry signal and leaves the tail ringing — the same reason `.echoOut` cuts
/// with the EQ's global gain rather than the fader.
struct EchoThrowDirective: Sendable, Equatable {
    /// Seconds into the overlap where the delay is engaged.
    var throwAt: TimeInterval
    /// Beat-synced delay time, seconds.
    var delayTime: TimeInterval
    var wetDryMix: Float = Self.throwWetMix
    var feedback: Float = Self.throwFeedback

    // MARK: - The tail, tamed (P2)

    /// **Wet level of the throw's tail, −4 dB against `.echoOut`'s.**
    ///
    /// A throw and an outro echo are not the same job, and P1 gave them the
    /// same numbers. `.echoOut` is a *departure*: the outgoing track fades into
    /// its own delay and nothing follows it for a while, so 70 % wet is the
    /// point. A throw rings on **over a track that has already started** — the
    /// slam lands on the same frame the dry signal is cut — so the same 70 %
    /// puts the old song's wet tail level with the new song's downbeat, which
    /// is what the field listen heard as the seam being cluttered rather than
    /// decisive.
    ///
    /// Four dB down in amplitude is 70 % × 10^(−4/20) ≈ 44 %: still plainly a
    /// throw, no longer competing with the thing it is handing over to. The
    /// number is a constant rather than a `Config` field because the compiler
    /// takes no config — it is deliberately a pure placement pass — and no
    /// existing knob fits; a sweep changes it here.
    static let throwWetMix: Float
        = TransitionAutomation.echoWetMix * pow(10, throwTailTrimDB / 20)
    /// The −4 dB itself, named so the reasoning above has something to point at
    /// and a sweep has one number to move.
    static let throwTailTrimDB: Float = -4

    /// **Shorter feedback than `.echoOut`'s.** Fewer repeats for the same
    /// reason: an outro tail may ring for as long as it likes because nothing
    /// is underneath it, and a throw's repeats are landing on the incoming
    /// track's first bars. 50 % → 30 % is roughly three audible repeats instead
    /// of six, so the tail is gone inside the first phrase rather than through
    /// it.
    static let throwFeedback: Float = 30
}

/// The compiled audio side of a score: two lanes and the directives that are
/// not gain.
struct WholeMixLanes: Sendable, Equatable {
    var outgoing = WholeMixLane()
    var incoming = WholeMixLane()
    var echoThrow: EchoThrowDirective?

    /// **The lanes carry the whole gain law for this hand-over.**
    ///
    /// A blend's fader curves and staged EQ are a *different gesture* from a
    /// cut, not a backdrop for one: cutting a deck the staged EQ has already
    /// stripped of its highs and mids cuts something that was barely there, and
    /// slamming an incoming deck whose low end is still 24 dB down slams a
    /// filtered track. So when a score owns the seam the renderer neutralizes
    /// both decks' fader and EQ automation and lets these two lanes say
    /// everything — the rates, and only the rates, still come from the plan.
    ///
    var ownsGainLaw = false

    var isPassThrough: Bool {
        outgoing.isPassThrough && incoming.isPassThrough && echoThrow == nil
    }
}

/// Applies whole-mix lanes to the two decks' source buffers.
///
enum WholeMixLaneLayer {

    struct Applied: Sendable, Equatable {
        /// Frames rewritten per side.
        var outgoingFrames: Int
        var incomingFrames: Int
    }

    enum LaneError: LocalizedError {
        case noOverlap
        case emptyWindow

        var errorDescription: String? {
            switch self {
            case .noOverlap: return "whole-mix lanes need an overlap; this plan has none"
            case .emptyWindow: return "the overlap window has no audio to shape"
            }
        }
    }

    static func apply(_ lanes: WholeMixLanes,
                      outgoing: TransitionAudioSide,
                      incoming: TransitionAudioSide,
                      overlap: TimeInterval) throws -> Applied {
        guard overlap > 0 else { throw LaneError.noOverlap }
        var frames = (outgoing: 0, incoming: 0)
        frames.outgoing = try apply(lanes.outgoing, to: outgoing, overlap: overlap)
        frames.incoming = try apply(lanes.incoming, to: incoming, overlap: overlap)
        return Applied(outgoingFrames: frames.outgoing, incomingFrames: frames.incoming)
    }

    /// One side. Returns how many frames were rewritten (0 for a pass-through
    /// lane, which is not touched at all).
    static func apply(_ lane: WholeMixLane, to side: TransitionAudioSide,
                      overlap: TimeInterval) throws -> Int {
        guard !lane.isPassThrough else { return 0 }
        guard let data = side.buffer.floatChannelData else { throw LaneError.emptyWindow }
        let sampleRate = side.buffer.format.sampleRate
        let channels = Int(side.buffer.format.channelCount)
        let start = max(0, min(Int(side.buffer.frameLength), side.overlapStartFrame))
        let wanted = Int((side.sourceAdvance(to: overlap) * sampleRate).rounded())
        let count = min(wanted, Int(side.buffer.frameLength) - start)
        guard count > 0 else { throw LaneError.emptyWindow }

        let gains = perSampleGains(lane, clock: side.clock, frames: count,
                                   sampleRate: sampleRate)
        for channel in 0..<channels {
            let pointer = data[channel] + start
            for i in 0..<count { pointer[i] *= gains[i] }
        }
        return count
    }

    /// The lane, sampled once per source frame.
    ///
    /// Exposed (and pure) so a test can assert where an edge lands without
    /// rendering anything.
    static func perSampleGains(_ lane: WholeMixLane,
                               clock: TransitionSourceClock,
                               frames: Int, sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 1, count: frames)
        guard let first = lane.points.first, let last = lane.points.last else { return out }

        // Every breakpoint on the *source* clock. Monotone by construction:
        // `sourceAdvance` is an integral of a positive rate.
        let sourceTimes = lane.points.map { clock.sourceAdvance(to: $0.t) }
        let firstGain = WholeMixLane.linear(first.gainDB)
        let lastGain = WholeMixLane.linear(last.gainDB)

        var cursor = 0
        for i in 0..<frames {
            let s = Double(i) / sampleRate
            if s <= sourceTimes[0] { out[i] = firstGain; continue }
            if s >= sourceTimes[sourceTimes.count - 1] { out[i] = lastGain; continue }
            while cursor + 1 < sourceTimes.count, sourceTimes[cursor + 1] <= s { cursor += 1 }
            let a = lane.points[cursor], b = lane.points[cursor + 1]
            let span = sourceTimes[cursor + 1] - sourceTimes[cursor]
            let u = span > 1e-12 ? (s - sourceTimes[cursor]) / span : 1
            // Interpolate in the lane's own (overlap-relative) parameter, so
            // the edge shape is the one the compiler wrote.
            out[i] = WholeMixLane.interpolate(a, b, at: a.t + (b.t - a.t) * u)
        }
        return out
    }
}
