import AppKit
import Testing
@testable import KumoneCore

@Suite struct NowPlayingSwipeTests {
    @Test(arguments: [false, true])
    func playerBarAcceptsUpwardSwipeWithEitherScrollingPreference(inverted: Bool) {
        var swipe = NowPlayingSwipe()
        let delta = CGSize(width: 0, height: inverted ? -30 : 30)
        let began = swipe.update(delta: delta, phase: .began, startedInRegion: true,
                                 directionInverted: inverted, direction: .both)
        let crossedThreshold = swipe.update(delta: delta, phase: .changed, startedInRegion: true,
                                            directionInverted: inverted, direction: .both)
        #expect(!began)
        #expect(crossedThreshold)
    }

    @Test(arguments: [false, true])
    func playerBarAcceptsDownwardSwipeWithEitherScrollingPreference(inverted: Bool) {
        var swipe = NowPlayingSwipe()
        let didToggle = swipe.update(delta: CGSize(width: 0, height: inverted ? 100 : -100), phase: .began,
                                     startedInRegion: true, directionInverted: inverted, direction: .both)
        #expect(didToggle)
    }

    @Test func reversingOneGestureCannotImmediatelyToggleThePageBack() {
        var swipe = NowPlayingSwipe()
        let first = swipe.update(delta: CGSize(width: 0, height: 60), phase: .began,
                                 startedInRegion: true, directionInverted: true, direction: .both)
        let reversed = swipe.update(delta: CGSize(width: 0, height: -120), phase: .changed,
                                    startedInRegion: true, directionInverted: true, direction: .both)
        let ended = swipe.update(delta: .zero, phase: .ended,
                                 startedInRegion: true, directionInverted: true, direction: .both)
        let nextGesture = swipe.update(delta: CGSize(width: 0, height: -60), phase: .began,
                                       startedInRegion: true, directionInverted: true, direction: .both)
        #expect(first)
        #expect(!reversed)
        #expect(!ended)
        #expect(nextGesture)
    }

    @Test(arguments: [false, true])
    func headerAcceptsDownwardSwipeWithEitherScrollingPreference(inverted: Bool) {
        var swipe = NowPlayingSwipe()
        let delta = CGSize(width: 0, height: inverted ? 30 : -30)
        let began = swipe.update(delta: delta, phase: .began, startedInRegion: true, directionInverted: inverted, direction: .both)
        let crossedThreshold = swipe.update(delta: delta, phase: .changed, startedInRegion: true, directionInverted: inverted, direction: .both)
        #expect(!began)
        #expect(crossedThreshold)
        // A completed dismissal must not fire again during the same gesture.
        let repeated = swipe.update(delta: delta, phase: .changed, startedInRegion: true, directionInverted: inverted, direction: .both)
        #expect(!repeated)
    }

    @Test func scrollingLyricsCannotBecomeAHeaderDismissal() {
        var swipe = NowPlayingSwipe()
        let began = swipe.update(delta: CGSize(width: 0, height: 30), phase: .began,
                                 startedInRegion: false, directionInverted: true, direction: .down)
        let enteredHeader = swipe.update(delta: CGSize(width: 0, height: 80), phase: .changed,
                                         startedInRegion: true, directionInverted: true, direction: .down)
        #expect(!began)
        #expect(!enteredHeader)
    }

    @Test func headerAcceptsUpwardButNotMostlyHorizontalGestures() {
        var swipe = NowPlayingSwipe()
        let upward = swipe.update(delta: CGSize(width: 0, height: -100), phase: .began,
                                  startedInRegion: true, directionInverted: true, direction: .both)
        let sideways = swipe.update(delta: CGSize(width: 100, height: 60), phase: .began,
                                    startedInRegion: true, directionInverted: true, direction: .both)
        #expect(upward)
        #expect(!sideways)
    }

    @Test func smallSeparateGesturesDoNotAccumulate() {
        var swipe = NowPlayingSwipe()
        for _ in 0..<3 {
            let began = swipe.update(delta: CGSize(width: 0, height: 20), phase: .began,
                                     startedInRegion: true, directionInverted: true, direction: .down)
            let ended = swipe.update(delta: .zero, phase: .ended,
                                     startedInRegion: true, directionInverted: true, direction: .down)
            #expect(!began)
            #expect(!ended)
        }
    }

    @Test func cancellationDiscardsTheGesture() {
        var swipe = NowPlayingSwipe()
        let began = swipe.update(delta: CGSize(width: 0, height: 40), phase: .began,
                                 startedInRegion: true, directionInverted: true, direction: .down)
        let cancelled = swipe.update(delta: CGSize(width: 0, height: 40), phase: .cancelled,
                                     startedInRegion: true, directionInverted: true, direction: .down)
        let continued = swipe.update(delta: CGSize(width: 0, height: 40), phase: .changed,
                                     startedInRegion: true, directionInverted: true, direction: .down)
        #expect(!began)
        #expect(!cancelled)
        #expect(!continued)
    }
}
