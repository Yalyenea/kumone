import Foundation

// Shared contracts between the playback engine, the analyzer, and the
// transition planner. See docs/automix-spec.md.

/// One of the engine's two player decks. Tracks alternate decks so a
/// transition can overlap the outgoing and incoming songs.
enum Deck: String, Sendable {
    case a, b

    var other: Deck { self == .a ? .b : .a }
}

/// Per-track beat/energy analysis, computed once in the background and
/// persisted by `AnalysisStore`, keyed by track ID and outliving the cached
/// audio it was computed from (spec §3, §4).
struct TrackAnalysis: Codable, Sendable {
    /// Bump when the algorithm changes; stale records are re-analyzed.
    static let currentVersion = 7

    /// One structural span of the track — what a listener would call the intro,
    /// a verse, the chorus (predev §2.1). Produced by `StructureSegmenter` from
    /// a beat-synchronous self-similarity matrix; empty whenever the analyzer is
    /// not confident enough to be worth acting on, so every consumer must have a
    /// path that works without it.
    struct Section: Codable, Sendable, Equatable {
        enum Kind: String, Codable, Sendable {
            case intro, verse, chorus, bridge, drop, outro
        }

        /// Snapped to a downbeat (both ends), so a cue taken from a boundary
        /// lands on the bar line.
        var start: TimeInterval
        var end: TimeInterval
        var kind: Kind
        /// How many sections share this one's cluster — a chorus repeats, a
        /// bridge does not. 1 means "this passage happens once".
        var repetition: Int
        /// Section-mean RMS over the track's peak RMS.
        var energy: Float
        /// Section-mean `vocalActivity` over the whole-track mean; 1 is an
        /// average-density passage, 0 an instrumental one.
        var vocalDensity: Float
    }

    let version: Int
    let bpm: Double
    /// 0–1; below the planner's threshold the track never beat-matches.
    let bpmConfidence: Double
    let beats: [TimeInterval]
    let downbeats: [TimeInterval]
    /// Candidate mix points, best first (8/16-bar grid × energy shifts).
    let phraseBoundaries: [TimeInterval]
    /// RMS at 1s granularity over the whole track.
    let rmsEnvelope: [Float]
    /// Where a natural outro fade begins, if the track has one.
    let outroFadeStart: TimeInterval?
    /// First strong downbeat after any intro silence/buildup.
    let introEnd: TimeInterval
    let duration: TimeInterval
    /// Whole-track timbre fingerprint: the L2-normalized mean *level-removed*
    /// 40-band log-mel frame, averaged over the loud half of the track. Each
    /// frame has its own across-band mean (loudness) subtracted first, so the
    /// vector is pure spectral shape and sums to zero; cosine distance between
    /// two tracks' profiles is then a shape correlation, and is the planner's
    /// style-compatibility signal. Empty for very short input.
    let melProfile: [Float]
    /// Detected musical key as a pitch class 0–11 (C = 0), nil when the
    /// track has no stable tonal center.
    let keyPitchClass: Int?
    /// Whether the detected key is minor (only meaningful with a key).
    let keyIsMinor: Bool
    /// 0–1 confidence of the key estimate; below the planner's threshold
    /// the key never influences decisions.
    let keyConfidence: Double
    /// Vocal-presence likelihood 0–1 at 1s granularity (same grid as
    /// `rmsEnvelope`). Empty when not computed.
    let vocalActivity: [Float]
    /// Whole-track mastered loudness: BS.1770-4 K-weighted **gated integrated
    /// loudness in LUFS** (v6). This is the per-track "how loud is this master"
    /// number the cross-track gain compensation trims against; see
    /// `LoudnessMeter` for why LUFS and not an RMS proxy. Nil when the track is
    /// too short or effectively silent — the compensation then leaves the deck
    /// at unity rather than guessing.
    var referenceLoudness: Double? = nil
    /// Sample peak of the 22.05 kHz mono analysis signal, in dBFS. Only used to
    /// keep a compensation *boost* from clipping; nil for a silent track.
    var peakDBFS: Double? = nil
    /// Contiguous structural sections covering the track, in time order (v7).
    /// **Empty is the normal, expected state** for anything the segmenter is not
    /// sure about (see `structureConfidence`), for tracks under ~64 beats, and
    /// for every sidecar written before v7 — consumers fall back to the energy
    /// heuristics (`phraseBoundaries`, `introEnd`, `outroFadeStart`).
    var sections: [Section] = []
    /// 0–1 confidence in `sections`: novelty-peak significance blended with how
    /// far apart the section clusters ended up. Below the segmenter's own gate
    /// the sections are dropped entirely and this is what they were dropped for.
    var structureConfidence: Double = 0
}

/// Expressive styling for a transition — the technique vocabulary the
/// strategy layer draws from per song pair. Mechanics (timing, rates)
/// stay in `TransitionPlan`; this describes *how* the hand-over sounds.
struct TransitionStyle: Sendable, Equatable {
    enum OutroEffect: Sendable, Equatable {
        /// Plain volume fade.
        case fade
        /// A high-pass sweep hollows the outgoing track out as it leaves.
        case filterSweep
        /// The outgoing track stops on the boundary and a delay tail rings out.
        case echoOut
    }

    let outroEffect: OutroEffect
    /// Staged three-band EQ hand-over (lows last) instead of the single
    /// low-shelf bass swap.
    let stagedEQ: Bool
    /// Beat-synced delay time (seconds) for `.echoOut`, when the planner
    /// knows the outgoing tempo. Nil → the engine derives its own (beat
    /// grid on beat-matched plans, otherwise a fixed 250 ms).
    var echoDelayTime: TimeInterval? = nil

    /// **Dominant-deck fader law** for a staged beat-matched blend: one deck
    /// owns the floor at every instant, instead of both meeting at −3 dB in
    /// the middle. Read only when `stagedEQ` is on and the plan is
    /// `.beatMatched`; see `TransitionAutomation.frame`.
    ///
    /// Defaulted **off** on the struct rather than on the planner, so every
    /// hand-written style — `.plain`, the console's overrides, every fixture
    /// in the tests — keeps the symmetric curves it has always had, and only a
    /// plan the planner built with `dominantDeckBlend` on asks for the new law.
    var dominantDeck: Bool = false
    /// Where the incoming deck waits under the outgoing one before the swap,
    /// as a fader level. See `TransitionPlanner.Config.preSwapPlateau` for
    /// where the number comes from.
    var preSwapPlateau: Float = 0.85
    /// A **transition score**: a few typed events on the bar grid around the
    /// seam, to be compiled into audio by `ScoreCompiler` and performed by the
    /// pre-rendered segment path (`docs/automix-score-predev.md`).
    ///
    /// The live path never performs one. Sample-accurate gestures need the
    /// segment renderer; a 20 ms automation tick cannot cut cleanly, and an
    /// approximated cut is worse than the blend it replaced (predev §1.2), so a
    /// segment that does not arm means the listener hears today's hand-over.
    var score: TransitionScore? = nil
    /// **What the seam was aimed at** (`TransitionAim`, predev §2.3). Written
    /// only alongside a `score`, and nil is again everything today.
    ///
    /// It is an *annotation*, not an instruction: the decision it records has
    /// already been made — the plan's `inPoint` was composed backwards from it,
    /// so a style stripped of this field still plays the aimed hand-over. What
    /// it buys is that the compiler can place the seam on the aim exactly
    /// rather than re-deriving it from the phrase grid, and that every report
    /// can say *what* the cut landed on rather than only where.
    var aim: TransitionAim? = nil
    /// Why `aim` is what it is — and, when it is nil, **why there was nothing
    /// to aim at**. One English sentence, carried rather than re-derived so the
    /// console, the panel and the seam history all print the same reason the
    /// planner actually acted on.
    ///
    /// Nil is "the aiming layer never ran", which is every unscored seam. A
    /// refusal is never silent: `aim=none (no structure)` is the interesting
    /// half of the A/B, and a bare `aim=none` reads as a missing feature.
    var aimDetail: String? = nil
    /// **What this hand-over was for** (`TransitionIntent`, P3, predev §2.4).
    ///
    /// An *annotation*, exactly like `aim`: by the time it is written the
    /// decision it records has already been taken — a `standDown` pair is
    /// already gapless, a `restrained` one already carries the short staged
    /// crossfade — so a style stripped of this field plays identically. What it
    /// buys is that the panel, the seam history, the journal and the feedback
    /// corpus can all say *which rule* produced the seam they are looking at,
    /// in the planner's own words, instead of guessing from the geometry.
    ///
    /// Nil is "the intent layer never ran", which is every shipped seam
    /// (`Config.intentEnabled` is false).
    var intent: TransitionIntent? = nil

    static let plain = TransitionStyle(outroEffect: .fade, stagedEQ: false)
}

/// What the strategy layer hands the engine: mechanics plus chosen styling.
struct PlannedTransition: Sendable {
    let plan: TransitionPlan
    let style: TransitionStyle
    /// **Transition gain ride**, in dB, for the *incoming* deck: held for the
    /// whole overlap and then released back to unity at
    /// `TransitionAutomation.rideReleaseDBPerSecond`. Negative holds the
    /// incoming track down, positive lifts it; see `TransitionPlanner.rideDB`
    /// for how it is derived and why only one deck rides.
    ///
    /// It lives here rather than in `TransitionPlan` (pure mechanics: when and
    /// how long) or `TransitionStyle` (how the hand-over *sounds*) because it
    /// is neither — it is a gain decision about one deck, of a piece with the
    /// load-time trim the engine already carries. Defaulted to 0 so
    /// `PlannedTransition(plan:style:)` and `.plain` keep every existing
    /// caller, and the whole gain path, bit-identical.
    var rideDB: Double = 0

    static func plain(_ plan: TransitionPlan) -> PlannedTransition {
        PlannedTransition(plan: plan, style: .plain)
    }
}

/// How to hand over from the current track to the next (spec §5).
enum TransitionPlan: Sendable {
    case beatMatched(BeatMatchedPlan)
    case crossfade(duration: TimeInterval, outPoint: TimeInterval, inPoint: TimeInterval)
    /// Tail-to-head, no overlap.
    case gapless
}

struct BeatMatchedPlan: Sendable {
    /// Phrase boundary in the outgoing track where the overlap starts.
    let outPoint: TimeInterval
    /// First downbeat of the incoming track to align to `outPoint`.
    let inPoint: TimeInterval
    let overlapBars: Int
    /// Playback-rate nudges so the grids line up; the incoming deck is let
    /// back to 1.0 after the overlap. How far each may bend is the planner's
    /// `maxRateDeviation` (step) or `rampMaxRateDeviation` (glide).
    let outgoingRate: Float
    let incomingRate: Float
    /// Seconds into the overlap where the low end swaps decks.
    let bassSwapOffset: TimeInterval
    /// Total overlap length in seconds at the blended tempo.
    let overlapDuration: TimeInterval

    // --- Tempo ramp (`TransitionPlanner.Config.tempoRampEnabled`). Both are 0
    // on a plan made with the ramp off, and 0 is what every path reads as "the
    // old step behaviour" — so a plan built before these fields existed, or by
    // a config with the knob down, decides and sounds exactly as it did.

    /// Seconds of the **outgoing track's own timeline** over which its deck
    /// glides 1.0 → `outgoingRate` before the seam. The glide is anchored so
    /// that it *finishes* one `TransitionAutomation.segmentHandoff` before
    /// `outPoint`; see `TransitionAutomation.tempoRamp`.
    var rampLeadSeconds: TimeInterval = 0
    /// Seconds over which the incoming deck is let back from `incomingRate` to
    /// 1.0 once it is the only thing audible. 0 → the legacy
    /// `TransitionAutomation.rateRestoreDuration`. Under
    /// `rampGlideBackFromSwap` this is only a *floor* on the glide's length,
    /// which normally runs longer; see `TransitionAutomation.incomingGlide`.
    var rampReleaseSeconds: TimeInterval = 0
    /// Whether the incoming deck starts walking back to unity **at the bass
    /// swap** rather than after the overlap — moving the phase-vocoder artifact
    /// off the deck that is about to be alone and onto the stretch where the
    /// outgoing track still masks it. False, the default, is the old
    /// hold-then-release and is what every plan built before the glide existed
    /// reads as. See `TransitionAutomation.incomingGlide`.
    var rampGlideBackFromSwap: Bool = false

    /// The same hand-over, entered at a different point of the **incoming**
    /// track — the one thing the aiming layer (predev §2.3) changes about a
    /// plan.
    ///
    /// Field-for-field a copy but for `inPoint`, deliberately written out
    /// rather than made a `var`: the plan is what the armed-plan comparison and
    /// the segment signature are keyed on, and every other field staying put is
    /// the promise that aiming moved the entry and nothing else. The out point,
    /// the bar count, both rates and the whole ramp are the outgoing track's
    /// and the gates' business, and aiming has no vote on any of them.
    func enteringIncoming(at inPoint: TimeInterval) -> BeatMatchedPlan {
        var moved = BeatMatchedPlan(
            outPoint: outPoint, inPoint: inPoint, overlapBars: overlapBars,
            outgoingRate: outgoingRate, incomingRate: incomingRate,
            bassSwapOffset: bassSwapOffset, overlapDuration: overlapDuration)
        moved.rampLeadSeconds = rampLeadSeconds
        moved.rampReleaseSeconds = rampReleaseSeconds
        moved.rampGlideBackFromSwap = rampGlideBackFromSwap
        return moved
    }
}

extension TransitionPlan {
    /// Seconds before the outgoing track's out point at which the incoming
    /// deck must already be loaded and scheduled.
    var outPoint: TimeInterval? {
        switch self {
        case .beatMatched(let plan): return plan.outPoint
        case .crossfade(_, let outPoint, _): return outPoint
        case .gapless: return nil
        }
    }
}
