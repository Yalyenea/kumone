import AppKit
import Testing
@testable import KumoneCore

@MainActor
@Suite(.serialized)
struct NowPlayingIdleTests {
    @Test func inactivityHidesControlsAndActivityRestoresTheirOriginalState() async throws {
        let window = makeWindow()
        let controller = NowPlayingIdleController(idleInterval: 0.04)
        defer {
            controller.stop()
            window.close()
        }
        let close = try #require(window.standardWindowButton(.closeButton))
        let zoom = try #require(window.standardWindowButton(.zoomButton))
        zoom.isHidden = true
        let frame = window.frame

        controller.setEnabled(true, in: window)
        try await waitForClean(controller)
        #expect(close.isHidden)
        #expect(window.frame == frame)
        // Routine SwiftUI refreshes must not wake an already idle page.
        controller.setEnabled(true, in: window)
        #expect(controller.isClean)

        controller.recordActivity()
        #expect(!controller.isClean)
        #expect(!close.isHidden)
        #expect(zoom.isHidden)
        try await waitForClean(controller)
        #expect(close.isHidden)
    }

    @Test(arguments: [false, true])
    func disablingCancelsDeadlineAndRestoresMouseDelivery(acceptedMovement: Bool) async throws {
        let window = makeWindow()
        let controller = NowPlayingIdleController(idleInterval: 0.04)
        defer {
            controller.stop()
            window.close()
        }
        window.acceptsMouseMovedEvents = acceptedMovement
        controller.setEnabled(true, in: window)
        #expect(window.acceptsMouseMovedEvents)
        controller.setEnabled(false, in: window)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.isClean)
        #expect(window.acceptsMouseMovedEvents == acceptedMovement)

        controller.setEnabled(true, in: window)
        try await waitForClean(controller)
        controller.setEnabled(false, in: window)
        #expect(!controller.isClean)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
        #expect(window.acceptsMouseMovedEvents == acceptedMovement)
    }

    @Test func activityKeepsThePageVisibleUntilInputStops() async throws {
        let window = makeWindow()
        let controller = NowPlayingIdleController(idleInterval: 0.3)
        defer {
            controller.stop()
            window.close()
        }
        controller.setEnabled(true, in: window)
        // Continue past the original deadline without replacing the window
        // or restarting the controller, as real mouse movement would.
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(100))
            #expect(!controller.isClean)
            controller.recordActivity()
        }
        try await waitForClean(controller)
    }

    @Test func switchingWindowsRestoresOldControlsAndStartsAFreshDeadline() async throws {
        let first = makeWindow()
        let second = makeWindow()
        let controller = NowPlayingIdleController(idleInterval: 0.04)
        defer {
            controller.stop()
            first.close()
            second.close()
        }
        controller.setEnabled(true, in: first)
        try await waitForClean(controller)
        controller.setEnabled(true, in: second)
        #expect(!controller.isClean)
        #expect(first.standardWindowButton(.closeButton)?.isHidden == false)
        try await waitForClean(controller)
        #expect(second.standardWindowButton(.closeButton)?.isHidden == true)
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        // Exercise real AppKit controls without showing a window or taking focus.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func waitForClean(_ controller: NowPlayingIdleController) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !controller.isClean, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.isClean)
    }
}
