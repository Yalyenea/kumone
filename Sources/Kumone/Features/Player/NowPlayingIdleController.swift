import AppKit
import SwiftUI

/// One deadline for the whole playback page, including its native window controls.
@MainActor
final class NowPlayingIdleController: ObservableObject {
    @Published private(set) var isClean = false
    @Published private(set) var isPreviewingTransport = false
    @Published var isShowingOptions = false

    private let idleInterval: TimeInterval
    private weak var window: NSWindow?
    private var eventMonitor: Any?
    private var timer: Timer?
    private var lastActivity: TimeInterval = 0
    private var acceptedMouseMovement = false
    private var hiddenButtons: [(button: NSButton, wasHidden: Bool)] = []

    init(idleInterval: TimeInterval = 10) {
        self.idleInterval = idleInterval
    }

    deinit {
        timer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    func setEnabled(_ enabled: Bool, in window: NSWindow?) {
        guard enabled, let window else {
            stop()
            return
        }
        guard self.window !== window else { return }
        stop()
        self.window = window
        acceptedMouseMovement = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        lastActivity = ProcessInfo.processInfo.systemUptime
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .mouseExited, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel, .keyDown, .flagsChanged
        ]) { [weak self] event in
            if let self, event.window === self.window {
                let transportBounds = CGRect(
                    x: 0, y: 0, width: event.window?.frame.width ?? 0,
                    height: Theme.Layout.playerBarHeight + 7
                )
                let isOverTransport = transportBounds.contains(event.locationInWindow)
                if event.type == .mouseExited {
                    if !isOverTransport { self.setTransportPreview(false) }
                } else {
                    self.recordActivity(previewingTransport: event.type == .mouseMoved && isOverTransport)
                }
            }
            return event
        }
        scheduleCheck(after: idleInterval)
    }

    func recordActivity(previewingTransport: Bool = false) {
        guard window != nil else { return }
        setTransportPreview(previewingTransport)
        lastActivity = ProcessInfo.processInfo.systemUptime
        guard isClean else { return }
        // Hovering at the bottom reveals transport without bringing the
        // window header back. Clicks and keyboard input still wake the page.
        guard !previewingTransport else { return }
        restoreWindowButtons()
        isClean = false
        scheduleCheck(after: idleInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        restoreWindowButtons()
        // The host may repeatedly disable monitoring while a popover is open.
        // Publishing the same value would trigger another SwiftUI update.
        if isClean { isClean = false }
        setTransportPreview(false)
        window?.acceptsMouseMovedEvents = acceptedMouseMovement
        window = nil
    }

    private func setTransportPreview(_ visible: Bool) {
        if isPreviewingTransport != visible { isPreviewingTransport = visible }
    }

    private func scheduleCheck(after interval: TimeInterval) {
        timer?.invalidate()
        // The default run-loop mode pauses the deadline while a menu is tracking.
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForInactivity() }
        }
    }

    private func checkForInactivity() {
        guard let window else { return }
        let remaining = idleInterval - (ProcessInfo.processInfo.systemUptime - lastActivity)
        if remaining > 0 {
            // Mouse movement only updates the timestamp; it never creates a
            // new timer or publishes SwiftUI state on every mouse event.
            scheduleCheck(after: remaining)
        } else if NSEvent.pressedMouseButtons != 0 || window.inLiveResize {
            scheduleCheck(after: idleInterval)
        } else {
            hiddenButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
                .map { ($0, $0.isHidden) }
            for entry in hiddenButtons { entry.button.isHidden = true }
            isClean = true
            timer = nil
        }
    }

    private func restoreWindowButtons() {
        for entry in hiddenButtons { entry.button.isHidden = entry.wasHidden }
        hiddenButtons.removeAll()
    }
}

/// Observes this window without placing a hit-test surface over the lyrics or record.
struct NowPlayingActivityMonitor: NSViewRepresentable {
    let controller: NowPlayingIdleController
    let isEnabled: Bool

    func makeNSView(context: Context) -> ActivityView {
        ActivityView()
    }

    func updateNSView(_ view: ActivityView, context: Context) {
        view.controller = controller
        view.isEnabled = isEnabled
        // AppKit can attach the host after SwiftUI's first update.
        DispatchQueue.main.async { view.synchronize() }
    }

    static func dismantleNSView(_ view: ActivityView, coordinator: ()) {
        view.isEnabled = false
        view.controller?.stop()
    }

    final class ActivityView: NSView {
        weak var controller: NowPlayingIdleController?
        var isEnabled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.synchronize() }
        }

        func synchronize() {
            controller?.setEnabled(isEnabled, in: window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    func hiddenDuringCleanPlayback(_ hidden: Bool) -> some View {
        // Keep layout and view identity stable so the record and lyrics do
        // not jump or restart their animations as controls fade away.
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
            .animation(AppAnimation.smooth, value: hidden)
    }
}
