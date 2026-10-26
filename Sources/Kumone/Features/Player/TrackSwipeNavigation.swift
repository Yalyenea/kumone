import AppKit
import SwiftUI

enum TrackSwipeDirection {
    case next, previous

    var sign: CGFloat { self == .next ? -1 : 1 }

    static func matching(_ translation: CGSize) -> Self? {
        guard abs(translation.width) >= 60,
              abs(translation.width) > abs(translation.height) * 1.5 else { return nil }
        return translation.width < 0 ? .next : .previous
    }
}

/// Lock the initial axis, and allow only one track change per finger contact.
struct TrackSwipeState {
    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var translation = CGSize.zero
    private(set) var didTrigger = false

    var isHorizontal: Bool { axis == .horizontal }
    var horizontalTranslation: CGFloat { translation.width }

    mutating func append(x: CGFloat, y: CGFloat) -> TrackSwipeDirection? {
        translation.width += x
        translation.height += y
        if axis == nil, max(abs(translation.width), abs(translation.height)) >= 10 {
            axis = abs(translation.width) > abs(translation.height) * 1.5
                ? .horizontal : .vertical
        }
        guard isHorizontal, !didTrigger,
              let direction = TrackSwipeDirection.matching(translation) else { return nil }
        didTrigger = true
        return direction
    }
}

/// Share one visual transition between the page and transport, whichever
/// surface receives the swipe. Audio navigation still runs exactly once.
@MainActor
final class TrackSwipePresentation: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var opacity = 1.0

    private var transitionTask: Task<Void, Never>?
    private var isCommitting = false
    private var pendingDirection: TrackSwipeDirection?
    private var reducesMotion = false

    func follow(_ distance: CGFloat, reduceMotion: Bool) {
        guard !isCommitting, !reduceMotion else { return }
        transitionTask?.cancel()
        transitionTask = nil
        offset = min(max(distance * 0.25, -36), 36)
        opacity = 1
    }

    func settle() {
        guard !isCommitting else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            offset = 0
            opacity = 1
        }
    }

    func commit(_ direction: TrackSwipeDirection, reduceMotion: Bool,
                changeTrack: @escaping () -> Bool) {
        guard !isCommitting else { return }
        transitionTask?.cancel()
        pendingDirection = direction
        reducesMotion = reduceMotion
        if reduceMotion {
            _ = changeTrack()
            pendingDirection = nil
            settle()
            return
        }

        isCommitting = true
        withAnimation(.easeIn(duration: 0.12)) {
            offset = direction.sign * 64
            opacity = 0
        }
        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            let changed = changeTrack()
            self.isCommitting = false
            self.transitionTask = nil
            if changed {
                self.trackDidChange()
            } else {
                // Previous may only restart the song; FM, offline lookup and
                // an audio hand-over can publish the new track later.
                if direction == .previous { self.pendingDirection = nil }
                self.settle()
            }
        }
    }

    func trackDidChange() {
        guard !isCommitting, let direction = pendingDirection else { return }
        pendingDirection = nil
        guard !reducesMotion else { return }
        transitionTask?.cancel()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = -direction.sign * 48
            opacity = 0
        }
        transitionTask = Task { @MainActor [weak self] in
            // Publish the incoming position before starting its entrance.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                self.offset = 0
                self.opacity = 1
            }
            self.transitionTask = nil
        }
    }

    func reset() {
        transitionTask?.cancel()
        transitionTask = nil
        isCommitting = false
        pendingDirection = nil
        offset = 0
        opacity = 1
    }
}

private struct TrackSwipeContent: ViewModifier {
    @EnvironmentObject private var presentation: TrackSwipePresentation
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: presentation.offset * scale)
            .opacity(presentation.opacity)
    }
}

private struct TrackSwipeNavigation: ViewModifier {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var presentation: TrackSwipePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var volumeBounds = CGRect.zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // Child drag gestures (scrubber and volume) keep priority.
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                            follow(value.translation.width)
                        }
                    }
                    .onEnded { value in
                        if let direction = TrackSwipeDirection.matching(value.translation) {
                            navigate(direction)
                        } else {
                            presentation.settle()
                        }
                    }
            )
            .coordinateSpace(name: VolumeSwipeBoundsKey.coordinateSpace)
            .onPreferenceChange(VolumeSwipeBoundsKey.self) { volumeBounds = $0 }
            .background {
                TrackpadTrackSwipe(enabled: !player.isScrubbing,
                                   volumeBounds: volumeBounds,
                                   onSwipe: navigate,
                                   onSlide: follow,
                                   onSlideEnded: presentation.settle,
                                   onVolumeSlide: { distance in
                                       player.volume = VolumeControl.volume(afterSliding: distance,
                                                                            from: player.volume)
                                   })
            }
    }

    private func follow(_ distance: CGFloat) {
        guard player.hasCurrentTrack, !player.isScrubbing else { return }
        presentation.follow(distance, reduceMotion: reduceMotion)
    }

    private func navigate(_ direction: TrackSwipeDirection) {
        guard player.hasCurrentTrack, !player.isScrubbing else { return }
        presentation.commit(direction, reduceMotion: reduceMotion) {
            let previousID = player.currentTrack?.id
            switch direction {
            case .next: player.next()
            case .previous: player.previous()
            }
            return player.currentTrack?.id != previousID
        }
    }
}

extension View {
    func trackSwipeNavigation() -> some View {
        modifier(TrackSwipeNavigation())
    }

    func trackSwipeContent(scale: CGFloat = 1) -> some View {
        modifier(TrackSwipeContent(scale: scale))
    }
}

/// The whole volume control reserves its scroll gesture before track navigation.
struct VolumeSwipeBoundsKey: PreferenceKey {
    static let coordinateSpace = "playerTrackSwipe"
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// SwiftUI's DragGesture handles pointer drags; two-finger trackpad swipes
/// arrive as scroll events instead. Scope the monitor to this view's bounds.
private struct TrackpadTrackSwipe: NSViewRepresentable {
    let enabled: Bool
    let volumeBounds: CGRect
    let onSwipe: (TrackSwipeDirection) -> Void
    let onSlide: (CGFloat) -> Void
    let onSlideEnded: () -> Void
    let onVolumeSlide: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeRegion {
        SwipeRegion()
    }

    func updateNSView(_ view: SwipeRegion, context: Context) {
        view.enabled = enabled
        view.volumeBounds = volumeBounds
        view.onSwipe = onSwipe
        view.onSlide = onSlide
        view.onSlideEnded = onSlideEnded
        view.onVolumeSlide = onVolumeSlide
    }

    static func dismantleNSView(_ view: SwipeRegion, coordinator: ()) {
        view.stopMonitoring()
    }

    final class SwipeRegion: NSView {
        var enabled = false
        var volumeBounds = CGRect.zero
        var onSwipe: ((TrackSwipeDirection) -> Void)?
        var onSlide: ((CGFloat) -> Void)?
        var onSlideEnded: (() -> Void)?
        var onVolumeSlide: ((CGFloat) -> Void)?
        private var monitor: Any?
        private var state = TrackSwipeState()
        private var startedInside = false
        private var adjustsVolume = false

        // Match SwiftUI's top-leading coordinates for the volume preference.
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            startedInside = false
            state = TrackSwipeState()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, let window, event.window === window,
                  !isHiddenOrHasHiddenAncestor, event.hasPreciseScrollingDeltas else { return event }

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                state = TrackSwipeState()
                let point = convert(event.locationInWindow, from: nil)
                startedInside = visibleRect.contains(point)
                adjustsVolume = volumeBounds.contains(point)
            }
            guard startedInside else { return event }

            // Momentum belongs to the completed swipe, never another track.
            if !event.momentumPhase.isEmpty {
                if event.momentumPhase.contains(.ended) { return event }
                return state.isHorizontal ? nil : event
            }
            guard !event.phase.isEmpty else { return event }
            // Let scroll views finish any tracking begun before axis locking.
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                if !adjustsVolume { onSlideEnded?() }
                if event.phase.contains(.cancelled) { startedInside = false }
                return event
            }

            // Use finger direction consistently even with natural scrolling off.
            let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let distance = event.scrollingDeltaX * sign
            let direction = state.append(x: distance, y: event.scrollingDeltaY * sign)
            if adjustsVolume, state.isHorizontal {
                onVolumeSlide?(distance)
            } else if !adjustsVolume, let direction {
                onSwipe?(direction)
            } else if !adjustsVolume, state.isHorizontal, !state.didTrigger {
                onSlide?(state.horizontalTranslation)
            }
            return state.isHorizontal ? nil : event
        }
    }
}
