import SwiftUI

/// Design tokens: color, radius, spacing, layout metrics.
enum Theme {
    /// NetEase red, tuned slightly warmer for macOS.
    static let accent = Color(red: 0.925, green: 0.286, blue: 0.286) // #EC4949
    static let accentDeep = Color(red: 0.788, green: 0.161, blue: 0.161) // #C92929

    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.973, green: 0.357, blue: 0.357), accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    enum Radius {
        static let badge: CGFloat = 4
        static let small: CGFloat = 6
        static let standard: CGFloat = 8
        static let large: CGFloat = 12
        static let panel: CGFloat = 10
    }

    enum Layout {
        static let titlebarHeight: CGFloat = 40
        static let contentInset: CGFloat = 24
        static let cardSize: CGFloat = 160
        static func fittedShelfCardSize(availableWidth: CGFloat, leadingInset: CGFloat, spacing: CGFloat = 16) -> CGFloat {
            let usableWidth = availableWidth - leadingInset - spacing
            // A zero-width proposal while the split view is resizing still needs one 1pt card.
            let visibleCount = max(1, Int(ceil((usableWidth + spacing) / (cardSize + spacing))))
            return max(1, (usableWidth - CGFloat(visibleCount - 1) * spacing) / CGFloat(visibleCount))
        }
        /// Row height for a shelf of cover cards: artwork, then up to two lines
        /// of title and one of subtitle.
        static let coverShelfHeight: CGFloat = 226
        /// Row height for a shelf of artist cards: circular artwork, one name.
        static let artistShelfHeight: CGFloat = 196
        static let playerBarHeight: CGFloat = 64
        /// The docked player reserves its own space below the page.
        static let playerChromeClearance: CGFloat = 0
        /// Extra breathing margin for scrollable content clearing chrome.
        static let scrollBreathingMargin: CGFloat = 8

        static let minWindowWidth: CGFloat = 760
        static let minWindowHeight: CGFloat = 480
        static let defaultWindowWidth: CGFloat = 1200
        static let defaultWindowHeight: CGFloat = 780
    }
}

/// Motion tokens (mirrors kaset's `AppAnimation`).
enum AppAnimation {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.easeInOut(duration: 0.35)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)

    static let staggerDelay = 0.04
    static let maxStaggerDelay = 0.4

    static func stagger(for index: Int) -> Double {
        min(Double(index) * staggerDelay, maxStaggerDelay)
    }
}

extension View {
    @ViewBuilder
    func compatScrollClipDisabled() -> some View {
        scrollClipDisabled()
    }

    /// Hides the toolbar background.
    @ViewBuilder
    func compatHiddenToolbarBackground() -> some View {
        toolbarBackgroundVisibility(.hidden, for: .automatic)
    }

    func panelSurface(in shape: some Shape) -> some View {
        background(Platform.windowBackgroundColor, in: shape)
    }
}
