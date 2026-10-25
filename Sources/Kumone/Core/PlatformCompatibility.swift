import AppKit
import SwiftUI

public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
public typealias PlatformView = NSView
public typealias PlatformFont = NSFont
public typealias PlatformViewRepresentable = NSViewRepresentable

public extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

public extension PlatformImage {
    /// Renders the image into a circle of the given point diameter.
    func circularCropped(diameter: CGFloat) -> PlatformImage {
        let target = NSImage(size: NSSize(width: diameter, height: diameter))
        target.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        NSBezierPath(ovalIn: rect).addClip()
        let sourceAspect = size.width / max(size.height, 1)
        var drawRect = rect
        if sourceAspect > 1 {
            drawRect.size.width = diameter * sourceAspect
            drawRect.origin.x = -(drawRect.width - diameter) / 2
        } else if sourceAspect < 1 {
            drawRect.size.height = diameter / sourceAspect
            drawRect.origin.y = -(drawRect.height - diameter) / 2
        }
        draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        target.unlockFocus()
        return target
    }

    var cgImageRef: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

public enum Platform {
    public static var isReduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static func copyToPasteboard(string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    public static var windowBackgroundColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}


extension View {
    /// Suppress the system focus ring on interactive controls and containers.
    @ViewBuilder
    func noFocusRing() -> some View {
        focusEffectDisabled()
    }
}

extension NSView {
    /// Suppresses AppKit's default exterior focus ring on non-text controls.
    func disableFocusRingsRecursively() {
        if !(self is NSTextField), !(self is NSTextView) {
            if focusRingType != .none {
                focusRingType = .none
            }
            if let cell = (self as? NSControl)?.cell, cell.focusRingType != .none {
                cell.focusRingType = .none
            }
        }
        for subview in subviews {
            subview.disableFocusRingsRecursively()
        }
    }
}

extension NSWindow {
    /// Prevents AppKit from auto-focusing the first control on window open or
    /// page transition while preserving active text fields and shortcut recording.
    @MainActor
    func clearAutoFocusIfNeeded() {
        autorecalculatesKeyViewLoop = false
        initialFirstResponder = nil
        contentView?.disableFocusRingsRecursively()
        for accessory in titlebarAccessoryViewControllers {
            accessory.view.disableFocusRingsRecursively()
        }
        if let responder = firstResponder,
           responder !== self,
           !(responder is NSText),
           !(responder is NSTextView),
           !(responder is ShortcutRecorderView.RecorderNSView) {
            makeFirstResponder(nil)
        }
    }
}
