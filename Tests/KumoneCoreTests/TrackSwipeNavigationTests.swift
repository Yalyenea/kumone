import Foundation
import Testing
@testable import KumoneCore

@Suite struct TrackSwipeNavigationTests {
    @Test func pointerDragsNeedDeliberateHorizontalMovement() {
        #expect(TrackSwipeDirection.matching(CGSize(width: -60, height: 10)) == .next)
        #expect(TrackSwipeDirection.matching(CGSize(width: 60, height: -10)) == .previous)
        #expect(TrackSwipeDirection.matching(CGSize(width: 59, height: 0)) == nil)
        #expect(TrackSwipeDirection.matching(CGSize(width: 80, height: 70)) == nil)
        #expect(TrackSwipeDirection.matching(CGSize(width: 0, height: 100)) == nil)
    }

    @Test func oneContactCanOnlyChangeOneTrack() {
        var swipe = TrackSwipeState()
        #expect(swipe.append(x: -20, y: 1) == nil)
        #expect(swipe.isHorizontal)
        #expect(swipe.append(x: -40, y: 1) == .next)
        #expect(swipe.append(x: -100, y: 0) == nil)
        #expect(swipe.append(x: 300, y: 0) == nil)

        swipe = TrackSwipeState()
        #expect(swipe.append(x: 60, y: 0) == .previous)
    }

    @Test func lyricScrollingCannotBecomeATrackSwipe() {
        var swipe = TrackSwipeState()
        #expect(swipe.append(x: 1, y: 15) == nil)
        #expect(swipe.append(x: -100, y: 0) == nil)
        #expect(!swipe.isHorizontal)
    }

    @Test func smallJitterDoesNotLockTheAxis() {
        var swipe = TrackSwipeState()
        #expect(swipe.append(x: 0, y: 2) == nil)
        #expect(swipe.append(x: -60, y: 0) == .next)
    }
}

@Suite @MainActor struct TrackSwipePresentationTests {
    @Test func repeatedSwipesDuringExitChangeOnlyOneTrack() async {
        let presentation = TrackSwipePresentation()
        let signal = AsyncStream<Void>.makeStream()
        var calls = 0
        presentation.commit(.next, reduceMotion: false) {
            calls += 1
            signal.continuation.yield(())
            return true
        }
        presentation.commit(.next, reduceMotion: false) {
            calls += 1
            return true
        }
        var events = signal.stream.makeAsyncIterator()
        await events.next()
        #expect(calls == 1)
        presentation.reset()
        signal.continuation.finish()
    }

    @Test func deferredTrackChangeRestoresContentThenEntersFromOppositeSide() async {
        let presentation = TrackSwipePresentation()
        let signal = AsyncStream<Void>.makeStream()
        presentation.commit(.next, reduceMotion: false) {
            signal.continuation.yield(())
            return false
        }
        var events = signal.stream.makeAsyncIterator()
        await events.next()
        #expect(presentation.opacity == 1)
        #expect(presentation.offset == 0)

        presentation.trackDidChange()
        #expect(presentation.offset > 0)
        #expect(presentation.opacity == 0)
        // A new drag can interrupt the entrance before its first frame.
        presentation.follow(-40, reduceMotion: false)
        #expect(presentation.opacity == 1)
        #expect(presentation.offset < 0)
        presentation.reset()
        signal.continuation.finish()
    }

    @Test func resetCancelsPendingNavigation() async throws {
        let presentation = TrackSwipePresentation()
        var calls = 0
        presentation.commit(.next, reduceMotion: false) {
            calls += 1
            return true
        }
        presentation.reset()
        try await Task.sleep(for: .milliseconds(180))
        #expect(calls == 0)
        #expect(presentation.offset == 0)
        #expect(presentation.opacity == 1)
    }

    @Test func reducedMotionNavigatesImmediatelyWithoutTranslation() {
        let presentation = TrackSwipePresentation()
        var calls = 0
        presentation.follow(-100, reduceMotion: true)
        presentation.commit(.next, reduceMotion: true) {
            calls += 1
            return true
        }
        #expect(calls == 1)
        #expect(presentation.offset == 0)
        #expect(presentation.opacity == 1)
    }
}
