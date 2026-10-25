import AppKit
import SwiftUI
import Testing
@testable import KumoneCore

@MainActor
@Suite struct MainWindowTitlebarTests {
    @Test(arguments: [420.0, 800.0, 1430.0])
    func immersiveHeaderReceivesMouseHitsAndNavigationRestores(width: Double) {
        // Keep the window off screen: this exercises AppKit's real hit-test
        // hierarchy without moving focus or touching the user's workspaces.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "HeaderHitTest")

        let content = NSView(frame: window.contentView!.bounds)
        window.contentView = content
        let buttons = [44.0, 76.0].map { inset in
            let button = NSButton(title: "Player action", target: nil, action: nil)
            button.frame = NSRect(x: content.bounds.maxX - inset,
                                  y: content.bounds.maxY - 34, width: 28, height: 28)
            content.addSubview(button)
            return button
        }
        let titlebar = MainWindowTitlebar()
        titlebar.update(content: AnyView(Text("Navigation")), in: window)
        let root = window.contentView!.superview!
        func receivesMouseHit(_ button: NSButton) -> Bool {
            root.layoutSubtreeIfNeeded()
            let point = root.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
            let hit = root.hitTest(point)
            return hit === button || hit?.isDescendant(of: button) == true
        }

        #expect(buttons.allSatisfy { !receivesMouseHit($0) })
        let originalContentLayout = window.contentLayoutRect
        titlebar.setFadedOut(true)
        #expect(buttons.allSatisfy(receivesMouseHit))
        #expect(window.contentLayoutRect == originalContentLayout)

        // Asynchronous SwiftUI refreshes must not reattach the invisible
        // navigation container over the player's buttons.
        titlebar.update(content: AnyView(Text("Updated navigation")), in: window)
        #expect(buttons.allSatisfy(receivesMouseHit))

        titlebar.setFadedOut(false)
        titlebar.setFadedOut(false)
        #expect(window.titlebarAccessoryViewControllers.filter { $0 === titlebar }.count == 1)
        #expect(buttons.allSatisfy { !receivesMouseHit($0) })
    }
}
