import AppKit
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

@Suite @MainActor struct VolumeSwipeTests {
    @Test func emptySiblingDoesNotEraseVolumeRegion() {
        let region = CGRect(x: 690, y: 19, width: 90, height: 26)
        var bounds = VolumeSwipeBoundsKey.defaultValue
        VolumeSwipeBoundsKey.reduce(value: &bounds) { region }
        VolumeSwipeBoundsKey.reduce(value: &bounds) { .zero }
        #expect(bounds == region)
    }

    @Test(arguments: [false, true])
    func horizontalContactOverVolumeDoesNotChangeTracks(inverted: Bool) {
        withRegion { view, window in
            var distance: CGFloat = 0
            var tracks = 0
            view.onVolumeSlide = { distance += $0 }
            view.onSwipe = { _ in tracks += 1 }
            let sign: CGFloat = inverted ? 1 : -1
            let began = ScrollEvent(window: window, x: 20 * sign, phase: .began, inverted: inverted)
            #expect(view.handle(began) == nil)
            // Keep the gesture's original target when the pointer leaves it.
            let changed = ScrollEvent(window: window, x: 80 * sign, phase: .changed, inverted: inverted)
            changed.point = CGPoint(x: 300, y: 32)
            #expect(view.handle(changed) == nil)
            #expect(distance == 100)
            #expect(tracks == 0)

            let momentum = ScrollEvent(window: window, x: 80 * sign, momentum: .changed, inverted: inverted)
            _ = view.handle(momentum)
            #expect(distance == 100)
        }
    }

    @Test func verticalScrollOverVolumePassesThrough() {
        withRegion { view, window in
            var distance: CGFloat = 0
            view.onVolumeSlide = { distance += $0 }
            let event = ScrollEvent(window: window, x: 1, y: 30, phase: .began)
            #expect(view.handle(event) === event)
            #expect(distance == 0)
        }
    }

    @Test func playbackPageCannotCaptureVolumeGestureOutsideItsBounds() {
        withRegion { bar, window in
            // AppKit allows visibleRect to extend beyond an unclipped view.
            // Reproduce the two sibling monitors used by the page and bar.
            let page = TrackpadTrackSwipe.SwipeRegion(frame: CGRect(x: 0, y: 64, width: 800, height: 400))
            bar.addSubview(page)
            page.enabled = true
            var tracks = 0
            var volumeDistance: CGFloat = 0
            page.onSwipe = { _ in tracks += 1 }
            bar.onVolumeSlide = { volumeDistance += $0 }
            let event = ScrollEvent(window: window, x: 80, phase: .began)
            let pointInPage = page.convert(event.locationInWindow, from: nil)
            #expect(!page.bounds.contains(pointInPage))
            #expect(page.visibleRect.contains(pointInPage))
            #expect(page.handle(event) === event)
            #expect(bar.handle(event) == nil)
            #expect(tracks == 0)
            #expect(volumeDistance == 80)
            page.stopMonitoring()
        }
    }

    private func withRegion(_ test: (TrackpadTrackSwipe.SwipeRegion, NSWindow) -> Void) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 64),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = TrackpadTrackSwipe.SwipeRegion(frame: CGRect(x: 0, y: 0, width: 800, height: 64))
        window.contentView = view
        view.enabled = true
        view.volumeBounds = CGRect(x: 690, y: 19, width: 90, height: 26)
        defer {
            view.stopMonitoring()
            window.close()
        }
        test(view, window)
    }

    // Feed native event handling directly; never post input to the user's UI.
    private final class ScrollEvent: NSEvent {
        private let targetWindow: NSWindow
        var point = CGPoint(x: 720, y: 32)
        private let delta: CGSize
        private let eventPhase: NSEvent.Phase
        private let momentum: NSEvent.Phase
        private let inverted: Bool

        init(window: NSWindow, x: CGFloat, y: CGFloat = 0,
             phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [], inverted: Bool = true) {
            targetWindow = window
            delta = CGSize(width: x, height: y)
            eventPhase = phase
            self.momentum = momentum
            self.inverted = inverted
            super.init()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override var window: NSWindow? { targetWindow }
        override var locationInWindow: NSPoint { point }
        override var scrollingDeltaX: CGFloat { delta.width }
        override var scrollingDeltaY: CGFloat { delta.height }
        override var phase: NSEvent.Phase { eventPhase }
        override var momentumPhase: NSEvent.Phase { momentum }
        override var hasPreciseScrollingDeltas: Bool { true }
        override var isDirectionInvertedFromDevice: Bool { inverted }
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
