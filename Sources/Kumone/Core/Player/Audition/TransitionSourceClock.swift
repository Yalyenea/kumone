import AVFoundation
import Foundation

/// Maps overlap time to source time for both score placement and audio rendering.
struct TransitionSourceClock: Sendable, Equatable {
    var rate: Double
    var glide: TransitionAutomation.IncomingGlide?

    func sourceAdvance(to elapsed: TimeInterval) -> TimeInterval {
        glide?.sourceAdvance(to: elapsed) ?? elapsed * rate
    }

    func overlapElapsed(atSource source: TimeInterval,
                        within limit: TimeInterval) -> TimeInterval {
        guard let glide else { return rate > 0 ? source / rate : 0 }
        return glide.overlapElapsed(atSource: source, within: limit)
    }
}

/// A deck's audio window and its overlap clock. The outgoing window includes pre-roll.
struct TransitionAudioSide {
    let buffer: AVAudioPCMBuffer
    let overlapStartFrame: Int
    let rate: Double
    var glide: TransitionAutomation.IncomingGlide? = nil

    var clock: TransitionSourceClock { TransitionSourceClock(rate: rate, glide: glide) }

    func sourceAdvance(to elapsed: TimeInterval) -> TimeInterval {
        clock.sourceAdvance(to: elapsed)
    }
}
