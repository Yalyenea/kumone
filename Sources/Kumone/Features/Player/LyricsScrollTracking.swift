import SwiftUI

/// Keeps `isUserScrolling` true while the person scrolls a lyrics list by hand
/// and for a few seconds after it comes to rest, so follow-the-song auto
/// scrolling does not yank the list back mid-read.
///
/// Scroll phases track pointer, trackpad, wheel and momentum input while
/// leaving out programmatic `scrollTo` animations.
private struct LyricsScrollTracking: ViewModifier {
    @Binding var isUserScrolling: Bool
    let onResume: () -> Void

    @State private var resumeTask: Task<Void, Never>?

    private static let holdDuration: Duration = .seconds(3)

    func body(content: Content) -> some View {
        Group {

                content.onScrollPhaseChange { _, phase in
                    switch phase {
                    case .interacting, .decelerating:
                        resumeTask?.cancel()
                        isUserScrolling = true
                    case .tracking:
                        // A touch that may still turn out to be a tap on a
                        // line, so it only holds a scroll already under way.
                        if isUserScrolling { resumeTask?.cancel() }
                    case .idle, .animating:
                        if isUserScrolling { scheduleResume() }
                    @unknown default:
                        break
                    }
                }

        }
        .onDisappear {
            // The flag lives in the parent, which can outlive this list (lyrics
            // reloading on a track change), so clear it with the timer or it
            // stays stuck on and the list never follows the song again.
            resumeTask?.cancel()
            isUserScrolling = false
        }
    }

    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled else { return }
            isUserScrolling = false
            onResume()
        }
    }
}

extension View {
    /// Tracks manual scrolling of a lyrics list; see `LyricsScrollTracking`.
    /// `onResume` runs once the hold after a manual scroll runs out.
    func lyricsScrollTracking(
        isUserScrolling: Binding<Bool>,
        onResume: @escaping () -> Void = {}
    ) -> some View {
        modifier(LyricsScrollTracking(isUserScrolling: isUserScrolling, onResume: onResume))
    }
}
