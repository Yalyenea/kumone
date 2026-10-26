import SwiftUI

/// Share trackpad navigation between the page header and the bottom player bar
/// without covering their buttons or intercepting clicks.
struct NowPlayingSwipeGesture: NSViewRepresentable {
    let direction: NowPlayingSwipe.Direction
    let onSwipe: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.direction = direction
        view.onSwipe = onSwipe
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stop()
        view.onSwipe = nil
    }

    final class MonitorView: NSView {
        var direction: NowPlayingSwipe.Direction = .down
        var onSwipe: (() -> Void)?
        private var monitor: Any?
        private var swipe = NowPlayingSwipe()

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.swipe.update(
                    delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
                    phase: event.phase,
                    startedInRegion: self.bounds.contains(point),
                    directionInverted: event.isDirectionInvertedFromDevice,
                    direction: self.direction
                ) {
                    self.onSwipe?()
                    return nil
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            swipe = NowPlayingSwipe()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Only a deliberate vertical gesture that starts in its own region can act.
/// Gesture state stays outside SwiftUI so scrolling does not redraw the page.
struct NowPlayingSwipe {
    enum Direction { case down, both }

    private var isTracking = false
    private var distance = CGSize.zero

    mutating func update(delta: CGSize, phase: NSEvent.Phase,
                         startedInRegion: Bool, directionInverted: Bool, direction: Direction) -> Bool {
        if phase.contains(.cancelled) {
            isTracking = false
            return false
        }
        if phase.contains(.began) {
            isTracking = startedInRegion
            distance = .zero
        }
        guard isTracking else { return false }
        defer { if phase.contains(.ended) { isTracking = false } }

        distance.width += delta.width
        // Follow the fingers' downward motion regardless of the system's
        // natural-scrolling preference, rather than the content's direction.
        distance.height += directionInverted ? delta.height : -delta.height
        let directedDistance = direction == .both ? abs(distance.height) : distance.height
        guard directedDistance >= 56, directedDistance > abs(distance.width) * 1.25 else { return false }
        isTracking = false
        return true
    }
}
