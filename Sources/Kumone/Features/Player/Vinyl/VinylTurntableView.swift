import QuartzCore
import SwiftUI

/// Classic floating record with a fixed light source and a slim lifting arm.
public struct VinylTurntableView: View {
    public let artworkImage: PlatformImage?
    public let isPlaying: Bool
    public let duration: TimeInterval
    public let trackId: Int?
    public let size: CGFloat
    public var onTap: (() -> Void)? = nil
    @State private var isTransitioningTrack = false
    @ObservedObject private var windowVisibility = MainWindowVisibility.shared

    public init(
        artworkImage: PlatformImage?,
        isPlaying: Bool,
        duration: TimeInterval = 0,
        trackId: Int? = nil,
        size: CGFloat = 280,
        onTap: (() -> Void)? = nil
    ) {
        self.artworkImage = artworkImage
        self.isPlaying = isPlaying
        self.duration = duration
        self.trackId = trackId
        self.size = size
        self.onTap = onTap
    }

    public var body: some View {
        let discSize = size
        let armHeight = discSize * 0.56
        let stageWidth = discSize * 1.16
        let stageHeight = discSize * 1.24 + 6

        return ZStack(alignment: .top) {
            // The platter and light remain stationary, like a record under
            // a room light. Only the grooves and paper label rotate.
            Circle()
                .fill(.black.opacity(0.18))
                .overlay { Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1) }
                .frame(width: discSize + 12, height: discSize + 12)
                .shadow(color: .black.opacity(0.32), radius: discSize * 0.06, y: discSize * 0.035)
                .padding(.top, discSize * 0.22 - 3)

            SpinningVinylDisc(
                artworkImage: artworkImage,
                discSize: discSize,
                spinning: isPlaying && !isTransitioningTrack
                    && windowVisibility.isVisible
            )
            .overlay { recordReflection(size: discSize) }
            .padding(.top, discSize * 0.22)
            .contentShape(Circle())
            .onTapGesture {
                onTap?()
            }
            .zIndex(1)

            VinylTonearmView(
                isPlaying: isPlaying && !isTransitioningTrack,
                duration: duration,
                height: armHeight
            )
            .offset(x: discSize * 0.03)
            .allowsHitTesting(false)
            .zIndex(2)
        }
        .frame(width: stageWidth, height: stageHeight, alignment: .top)
        .onChange(of: trackId) { _ in
            // Temporarily lift tonearm on track change
            isTransitioningTrack = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                isTransitioningTrack = false
            }
        }
    }

    private func recordReflection(size: CGFloat) -> some View {
        Circle()
            .fill(AngularGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.10), location: 0.12),
                    .init(color: .clear, location: 0.24),
                    .init(color: .clear, location: 0.50),
                    .init(color: .white.opacity(0.07), location: 0.62),
                    .init(color: .clear, location: 0.76),
                    .init(color: .clear, location: 1)
                ], center: .center, angle: .degrees(-40)
            ))
            .frame(width: size, height: size)
            .mask {
                Circle().strokeBorder(lineWidth: size * 0.19)
                    .frame(width: size, height: size)
            }
            .allowsHitTesting(false)
    }

}

// MARK: - Disc rotation on the layer

/// Spins the disc on its own layer instead of a SwiftUI `TimelineView`.
///
/// The `TimelineView` re-evaluated the record — and with it the page's layout
/// around the whole stage — on every display frame while the song played,
/// worth a large share of a core. Rotating a `CALayer` is a compositing
/// change nothing above the hosted disc ever hears about, and
/// `RecordRotationState` still owns the angle math, so pausing and resuming
/// stay jump-free.
private final class DiscSpinController {
    private let layer: CALayer
    private var state = RecordRotationState()

    init(layer: CALayer) {
        self.layer = layer
    }

    func setSpinning(_ spinning: Bool) {
        if spinning {
            guard !state.isAnimating else { return }
            state.start(at: Date())
            // Core Animation measures angles the other way round from
            // SwiftUI: the record turns clockwise, which is a *negative*
            // z-rotation on a layer.
            let from = -state.currentAngle(at: Date()) * .pi / 180
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setValue(from, forKeyPath: "transform.rotation.z")
            CATransaction.commit()
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = from
            animation.toValue = from - 2 * .pi
            animation.duration = 360 / state.degreesPerSecond
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "vinyl-spin")
        } else {
            guard state.isAnimating else { return }
            state.stop(at: Date())
            // Freeze where the layer actually is on screen, not where the
            // animation started, or the disc snaps back a whole turn.
            if let onScreen = layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.setValue(onScreen, forKeyPath: "transform.rotation.z")
                CATransaction.commit()
                state.reset(to: -onScreen * 180 / .pi)
            }
            layer.removeAnimation(forKey: "vinyl-spin")
        }
    }
}

private struct SpinningVinylDisc: PlatformViewRepresentable {
    let artworkImage: PlatformImage?
    let discSize: CGFloat
    let spinning: Bool

    func makeNSView(context: Context) -> VinylDiscHost {
        let host = VinylDiscHost(artworkImage: artworkImage, size: discSize)
        host.spin.setSpinning(spinning)
        return host
    }

    func updateNSView(_ host: VinylDiscHost, context: Context) {
        host.update(artworkImage: artworkImage, size: discSize)
        host.spin.setSpinning(spinning)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VinylDiscHost, context: Context) -> CGSize? {
        CGSize(width: discSize + 6, height: discSize + 6)
    }
}

/// Hosts the record and takes no hits: taps and swipes belong to the SwiftUI
/// gestures wrapped around this representable.
///
/// AppKit anchors a view's backing layer at its origin, so the stage's origin
/// is placed *on the disc's centre* and the record laid out around it:
/// rotating the stage's layer then spins the disc in place, instead of
/// swinging it around the stage's corner.
private final class VinylDiscHost: NSView {
    private let stage = NSView()
    private let record: NSHostingView<VinylRecordView>
    private(set) lazy var spin = DiscSpinController(layer: stage.layer ?? CALayer())

    init(artworkImage: PlatformImage?, size: CGFloat) {
        record = NSHostingView(rootView: VinylRecordView(artworkImage: artworkImage, size: size))
        super.init(frame: .zero)
        wantsLayer = true
        stage.wantsLayer = true
        addSubview(stage)
        stage.addSubview(record)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(artworkImage: PlatformImage?, size: CGFloat) {
        // Cursor and visibility changes must not rebuild the static grooves.
        guard record.rootView.artworkImage !== artworkImage || record.rootView.size != size else { return }
        record.rootView = VinylRecordView(artworkImage: artworkImage, size: size)
    }

    override func layout() {
        super.layout()
        stage.frame = CGRect(x: bounds.midX, y: bounds.midY,
                             width: bounds.width, height: bounds.height)
        record.frame = CGRect(x: -bounds.midX, y: -bounds.midY,
                              width: bounds.width, height: bounds.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
