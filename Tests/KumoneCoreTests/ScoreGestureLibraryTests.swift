import Testing
@testable import KumoneCore
import Foundation

// 转场即乐谱 P4: the three gestures the library was missing, and the template
// layer that decides which one a pair is offered.
//
// The fixtures are `TransitionScoreTests`': the same mathematically exact
// 120 BPM grid, the same 2 s bars, the same 16 s beat-matched plan. That is
// deliberate — every claim below is about *where an edge lands*, and two files
// with two ideas of what a bar is would be testing arithmetic rather than the
// compiler.

/// A style carrying a score **and** an aim — which is what every P4 gesture
/// past the plain cut is conditional on, and what P1's fixtures had no reason
/// to build.
private func aimedStyle(_ score: TransitionScore?, _ aim: TransitionAim?) -> TransitionStyle {
    var style = scoredStyle(score)
    style.aim = aim
    style.aimDetail = aim.map { "fixture aim at \($0.label)" }
    return style
}

private func compile(_ score: TransitionScore, plan: BeatMatchedPlan,
                     aim: TransitionAim?,
                     outgoing: TrackAnalysis = ScoreFixtures.analysis(bpm: 120),
                     incoming: TrackAnalysis = ScoreFixtures.analysis(bpm: 120))
    -> ScoreCompiler.Compilation {
    ScoreCompiler.compile(
        score,
        planned: PlannedTransition(plan: .beatMatched(plan), style: aimedStyle(score, aim)),
        outgoing: outgoing, incoming: incoming, outgoingURL: nil)
}

// MARK: - The template layer

@Suite struct ScoreTemplateSelectionTests {

    private func material(
        aim: TransitionAim?,
        hasLyrics: Bool = false
    ) -> ScoreTemplate.Material {
        ScoreTemplate.Material(aim: aim, hasLyrics: hasLyrics)
    }

    private let drop = TransitionAim(target: .drop, time: 8, leadBars: 4)
    private let core = TransitionAim(target: .core, time: 8, leadBars: 4)

    @Test func theLadderTakesTheMostImpactfulRungThatQualifies() {
        let config = TransitionPlanner.Config.standard
        // Everything qualifying: the silence wins, because it is the biggest
        // thing the library can do and the ladder is ordered by impact.
        let top = ScoreTemplate.select(family: .cutCulture,
                                       material: material(aim: drop, hasLyrics: true),
                                       config: config)
        #expect(top?.template == .tensionCut(beats: 1))
        #expect(top?.score == .tensionCut(beats: 1))
        #expect(top?.passedOver.isEmpty == true)

        // No drop to promise: the throw is next, and the rung above says why it
        // stood down rather than going quiet about it.
        let thrown = ScoreTemplate.select(family: .cutCulture,
                                          material: material(aim: core, hasLyrics: true),
                                          config: config)
        #expect(thrown?.template == .throwCut)
        #expect(thrown?.passedOver.count == 1)
        #expect(thrown?.passedOver.first?.contains("tensionCut") == true)

        // No words either: the plain cut, which is P1's answer and the floor of
        // the ladder — a `cutCulture` pair always gets *something*.
        let plain = ScoreTemplate.select(family: .cutCulture,
                                         material: material(aim: nil), config: config)
        #expect(plain?.template == .cut)
        #expect(plain?.score == .cutOnOne())
        #expect(plain?.passedOver.count == 2)
    }

    @Test func theCutLadderOwnsTheSeam() {
        // Only cutCulture offers a score template.
        let config = TransitionPlanner.Config.standard
        for template in ScoreTemplate.ladder(.cutCulture, config: config) {
            #expect(template.score.ownsSeam)
            #expect(template.family == .cutCulture)
        }
        // The control arm is on neither ladder: a control the planner could
        // pick on its own is not a control.
        #expect(!ScoreTemplate.ladder(.cutCulture, config: config).contains(.cutOnly))
    }

    @Test func theTensionCutIsOnlyOfferedIntoSomethingWorthWaitingFor() {
        var config = TransitionPlanner.Config.standard
        // The rule the gesture lives by. A verse landing is the predev's
        // malfunction, and it is refused by name rather than quietly.
        guard case .no(let verse) = ScoreTemplate.tensionCut(beats: 1)
            .qualify(material(aim: core), config: config) else {
            Issue.record("a core landing must not get a tension cut"); return
        }
        #expect(verse.contains("not on a drop or a chorus"))

        // No aim at all is the same answer for a stronger reason.
        guard case .no(let unaimed) = ScoreTemplate.tensionCut(beats: 1)
            .qualify(material(aim: nil), config: config) else {
            Issue.record("an unaimed seam must not get a tension cut"); return
        }
        #expect(unaimed.contains("not aimed"))

        // A chorus counts; so does a drop.
        for target in [TransitionAim.Target.drop, .chorus] {
            let aim = TransitionAim(target: target, time: 8, leadBars: 4)
            guard case .yes = ScoreTemplate.tensionCut(beats: 1)
                .qualify(material(aim: aim), config: config) else {
                Issue.record("\(target) should qualify"); return
            }
        }

        // And an aim that lands on the *end of the overlap* is a blend's aim:
        // there is no cut for the silence to sit in front of.
        let blendAim = TransitionAim(target: .drop, time: 8, leadBars: 4, landing: .overlapEnd)
        guard case .no(let blended) = ScoreTemplate.tensionCut(beats: 1)
            .qualify(material(aim: blendAim), config: config) else {
            Issue.record("a blend's aim must not get a tension cut"); return
        }
        #expect(blended.contains("no cut"))

        // Independently switchable, which is the predev's roll-back mitigation.
        config.scoreTensionCutEnabled = false
        #expect(ScoreTemplate.select(family: .cutCulture,
                                     material: material(aim: drop, hasLyrics: true),
                                     config: config)?.template == .throwCut)
    }

}

// MARK: - The slam and the tension cut

@Suite struct SlamAndTensionCutCompileTests {

    private let drop = TransitionAim(target: .drop, time: 8, leadBars: 4)

    @Test func theSlamIsTheEventAndItsAbsenceIsAnInstruction() throws {
        // P1 wrote `slamIn` into every score and the compiler ignored it: the
        // incoming lane's rise was hard-wired to the seam. P4 made the event
        // the thing that decides, which is what lets the slam be A/B'd against
        // its own absence — two renders differing in one lane's middle two
        // breakpoints and nothing else in the pipeline.
        let plan = matchedPlan()
        let slammed = compile(.cutOnOne(), plan: plan, aim: drop)
        let softened = compile(.cutOnly(), plan: plan, aim: drop)
        let a = try #require(slammed.lanes), b = try #require(softened.lanes)

        // The outgoing side is the same cut in both — the difference is
        // entirely the entry.
        #expect(a.outgoing == b.outgoing)
        #expect(a.ownsGainLaw && b.ownsGainLaw)

        let edge = WholeMixLane.cutEdgeSeconds
        let seam = slammed.seamOffset
        #expect(seam == softened.seamOffset)
        #expect(a.incoming.points.map(\.t) == [0, seam - edge, seam, plan.overlapDuration])
        #expect(a.incoming.points.map(\.gainDB)
            == [WholeMixLane.minGainDB, WholeMixLane.minGainDB, 0, 0])
        // The control arm rises over a bar starting *at* the cut — the mildest
        // honest thing an owned gain law can do.
        let bar = 2.0
        #expect(b.incoming.points.map(\.t) == [0, seam, seam + bar, plan.overlapDuration])
        // Which is audible as a level rather than an event: a quarter-bar after
        // the cut the slam is at full gain and the control arm is nowhere near.
        #expect(a.incoming.gain(at: seam + 0.5) == 1)
        #expect(b.incoming.gain(at: seam + 0.5) < 0.4)
    }

    @Test func theSilenceIsExactlyNBeatsAtTheBentRate() throws {
        // The claim the tension cut stands on. The silence is a span ending on
        // the seam, so performing it is the outgoing cut edge moved back N
        // beats — and "N beats" is measured on the outgoing song's own bar,
        // divided by the rate it is bent to, or the gesture is a beat of
        // something-nearly-a-beat.
        let rate: Float = 1.04
        let plan = matchedPlan(outgoingRate: rate)
        for beats in [0.5, 1.0, 2.0] {
            let c = compile(.tensionCut(beats: beats), plan: plan, aim: drop)
            let lanes = try #require(c.lanes)
            #expect(c.degradations.isEmpty)
            // Points: unity, unity, silence, silence. The third is the cut.
            let cutAt = lanes.outgoing.points[2].t
            let beat = 2.0 / Double(TransitionScore.beatsPerBar)
            #expect(abs((c.seamOffset - cutAt) - beats * beat / Double(rate)) < 1e-9)
            #expect(lanes.outgoing.points[2].gainDB == WholeMixLane.minGainDB)

            // …and it really is silence: both decks at the floor, everywhere
            // between the cut and the slam's own edge.
            let edge = WholeMixLane.cutEdgeSeconds
            let floor = WholeMixLane.linear(WholeMixLane.minGainDB) + 1e-6
            for step in stride(from: cutAt, through: c.seamOffset - edge, by: 0.005) {
                #expect(lanes.outgoing.gain(at: step) <= floor)
                #expect(lanes.incoming.gain(at: step) <= floor)
            }
            // The slam still lands on the seam; it does not come back N beats
            // early with the cut.
            #expect(lanes.incoming.points[2].t == c.seamOffset)
            #expect(c.label == String(format: "tensionCut(%g)+cutOnOne", beats))
        }
    }

    @Test func theSilenceLandsOnTheSampleTheCompilerNamed() throws {
        // Sample-exactness, asserted where it is decided: the per-sample gain
        // walk. The frame the compiler named is silent and the one before the
        // edge is not — which is the entire reason this gesture lives in the
        // segment path and never on the live engine's 20 ms tick.
        let plan = matchedPlan()
        let c = compile(.tensionCut(beats: 1), plan: plan, aim: drop)
        let lanes = try #require(c.lanes)
        let sampleRate = 44_100.0
        let gains = WholeMixLaneLayer.perSampleGains(
            lanes.outgoing, clock: TransitionSourceClock(rate: 1),
            frames: Int(plan.overlapDuration * sampleRate), sampleRate: sampleRate)
        let cutAt = lanes.outgoing.points[2].t
        let cutFrame = Int((cutAt * sampleRate).rounded())
        let edgeFrames = Int((WholeMixLane.cutEdgeSeconds * sampleRate).rounded())
        #expect(gains[cutFrame] <= WholeMixLane.linear(WholeMixLane.minGainDB) + 1e-6)
        #expect(gains[cutFrame - edgeFrames - 1] == 1)
        // Nothing in between is unity either: the edge is a fall, not a step at
        // the end of a plateau.
        #expect(gains[cutFrame - edgeFrames / 2] < 1)
    }

    @Test func aTensionCutThatStopsBeingAimedDegradesRatherThanPlaysWrong() throws {
        // The compiler re-checks the tension cut's one rule where the aim is
        // final, because between the planner and here the aim can be dropped —
        // a plan override moved the seam and the compiler fell back to phrase
        // placement. A beat of silence in front of a bar line nobody was
        // waiting for is not a smaller gesture, it is a fault.
        let plan = matchedPlan()
        let core = TransitionAim(target: .core, time: 8, leadBars: 4)
        let c = compile(.tensionCut(beats: 1), plan: plan, aim: core)
        let lanes = try #require(c.lanes)
        #expect(c.didCompile)
        #expect(c.label == "cutOnOne")
        #expect(c.degradations.count == 1)
        #expect(c.degradations[0].contains("静默"))
        // The cut is exactly where a plain cut-on-one would have put it.
        #expect(lanes.outgoing.points[2].t == c.seamOffset)
    }

    @Test func aSilenceThatWillNotFitInTheWindowThrowsTheWholeScoreAway() {
        // All-or-nothing, per score, with a sentence. A tension cut whose
        // silence would have to start before the overlap did cannot be played,
        // and half of it is not a smaller version of it.
        let tight = matchedPlan(overlap: 4, bassSwapOffset: 0.05)
        let c = compile(.tensionCut(beats: 4), plan: tight,
                        aim: TransitionAim(target: .drop, time: 0, leadBars: 1))
        #expect(!c.didCompile)
        #expect(c.refusalReason != nil)
    }
}

// MARK: - The fall-back path, still byte-identical

@Suite struct GestureLibraryByteIdentityTests {

    @Test func theShippedConfigDecidesNothingWithAnyOfTheNewKnobs() {
        // The P4 knobs are only ever read from inside `ScoreTemplate`, which is
        // only reached when a family was offered, which needs `scoreEnabled`.
        // Asserted structurally rather than trusted: at the shipped config
        // there is no family, so there is nothing for them to decide.
        let confident = ScoreFixtures.analysis(bpm: 120, duration: 240, confidence: 0.99)
        #expect(TransitionPlanner.scoreFamily(outgoing: confident, incoming: confident,
                                              config: .standard) == nil)
        // …and the defaults are the ones the CLI builds its A/B templates from,
        // so a forced render is the gesture the planner would have offered.
        #expect(TransitionPlanner.Config.standard.scoreTensionCutBeats
                == TransitionScore.defaultTensionCutBeats)
        // Every new knob is on the tuning surface, or it cannot be swept.
        let names = Set(TransitionPlanner.Config.fields.map(\.name))
        for knob in ["scoreTensionCutEnabled", "scoreTensionCutBeats"] {
            #expect(names.contains(knob))
        }
    }

    @Test func theStandardConfigIsStillTheStandardConfig() {
        // The pin the whole "byte-identical fall-back" claim rests on: changing
        // gesture controls must not move unrelated defaults.
        #expect(TransitionPlanner.Config.standard.diffFromStandard.isEmpty)
        #expect(TransitionPlanner.Config.standard.scoreEnabled == false)
        #expect(TransitionPlanner.Config.standard.intentEnabled == false)
    }
}
