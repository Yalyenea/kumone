import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 640
            let diameter: CGFloat = compact ? 26 : 32
            let gap: CGFloat = compact ? 6 : 10
            let transportWidth = diameter * 4 + 36 + gap * 4
            let sideWidth = min(240, max(0, (proxy.size.width - transportWidth) / 2 - 20))

            // Reserve equal side regions around the transport. Even the
            // narrow layout keeps every action visible and Play centred.
            ZStack {
                HStack(spacing: 0) {
                    songInfoSection(compact: compact, diameter: diameter)
                        .frame(width: sideWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    optionsSection(compact: compact, diameter: diameter,
                                   showsQuality: proxy.size.width >= 1000)
                        .frame(width: sideWidth, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                transportControls(diameter: diameter, gap: gap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: Theme.Layout.playerBarHeight)
        .background {
            if !player.showNowPlaying {
                Platform.windowBackgroundColor
            }
        }
        .overlay(alignment: .top) { ScrubberLane().offset(y: -7) }
    }

    private func songInfoSection(compact: Bool, diameter: CGFloat) -> some View {
        HStack(spacing: compact ? 5 : 8) {
            artworkButton(size: compact ? 32 : 40)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: player.currentTrack?.name ?? String(localized: "未在播放"))
                    .frame(height: 17)
                Text(player.currentTrack?.artistNames ?? "Kumone")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(player.currentTrack?.artistNames ?? "Kumone")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let track = player.currentTrack {
                LikeButton(trackID: track.id, size: compact ? 14 : 16, diameter: diameter)
            }
        }
    }

    private func artworkButton(size: CGFloat) -> some View {
        Button {
            guard player.hasCurrentTrack else { return }
            withAnimation(AppAnimation.smooth) { player.showNowPlaying.toggle() }
        } label: {
            CachedAsyncImage(url: player.currentTrack?.album.picUrl?.resizedImageURL(128))
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        }
        .buttonStyle(.pressable)
        .noFocusRing()
        .help(player.showNowPlaying ? "收起播放页" : "打开播放页")
        .accessibilityLabel(player.showNowPlaying ? "收起播放页" : "打开播放页")
    }

    private func transportControls(diameter: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            PlayerIconButton(
                icon: player.isFMMode ? "wave.3.right" : player.playbackMode.symbolName,
                size: 16, diameter: diameter,
                isActive: player.playbackMode != .ordered,
                disabled: player.isFMMode
            ) { player.cyclePlaybackMode() }
            .help(player.isFMMode ? String(localized: "私人漫游中") : player.playbackMode.displayName)
            .accessibilityLabel(player.isFMMode ? String(localized: "私人漫游中") : player.playbackMode.displayName)

            PlayerIconButton(icon: player.isFMMode ? "trash" : "backward.end.fill",
                             size: 17, diameter: diameter) {
                if player.isFMMode { player.fmTrash() } else { player.previous() }
            }
            .help(player.isFMMode ? "不喜欢，换一首" : "上一首")
            .accessibilityLabel(player.isFMMode ? "不喜欢，换一首" : "上一首")

            playPauseButton

            PlayerIconButton(icon: "forward.end.fill", size: 17, diameter: diameter) {
                player.next()
            }
            .help("下一首")
            .accessibilityLabel("下一首")

            PlayerIconButton(icon: "list.bullet", size: 16, diameter: diameter,
                             isActive: player.activePanel == .queue, disabled: player.isFMMode) {
                player.activePanel = player.activePanel == .queue ? nil : .queue
            }
            .help("播放队列")
            .accessibilityLabel("播放队列")
        }
        .disabled(!player.hasCurrentTrack)
    }

    private var playPauseButton: some View {
        Button { player.togglePlayPause() } label: {
            ZStack {
                Circle().fill(Theme.accent).frame(width: 36, height: 36)
                if player.isBuffering && player.isPlaying {
                    ProgressView().controlSize(.small).tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying ? 0 : 1)
                        .contentTransition(.opacity)
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
        .help(player.isPlaying ? "暂停" : "播放")
    }

    private func optionsSection(compact: Bool, diameter: CGFloat, showsQuality: Bool) -> some View {
        HStack(spacing: compact ? 3 : 8) {
            if showsQuality, let level = player.servedQuality,
               let quality = AudioQuality(rawValue: level) {
                QualityTag(text: quality.badge)
            }
            PlayerIconButton(icon: "inset.filled.bottomthird.square", size: 16,
                             diameter: diameter, isActive: settings.showDesktopLyrics) {
                settings.showDesktopLyrics.toggle()
            }
            .help("桌面歌词")
            .accessibilityLabel("桌面歌词")
            RoutePickerButton(diameter: diameter, glyphSize: 16,
                              tint: .primary, background: .clear)
            VolumeControl(compact: compact)
        }
    }
}

private extension PlaybackMode {
    var symbolName: String {
        switch self {
        case .ordered: return "arrow.right"
        case .shuffled: return "shuffle"
        case .repeatOne: return "repeat.1"
        case .autoMix: return "wand.and.stars"
        }
    }

}

// MARK: - Icon button

struct PlayerIconButton: View {
    let icon: String
    var size: CGFloat = 14
    var diameter: CGFloat = 32
    var isActive = false
    var disabled = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .frame(width: diameter, height: diameter)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(backgroundColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .noFocusRing()
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .onHover { isHovering = $0 }
        .animation(AppAnimation.quick, value: isHovering)
    }

    private var backgroundColor: Color {
        let base: Color = colorScheme == .dark ? .white : .black
        if isHovering, !disabled { return base.opacity(0.08) }
        return .clear
    }
}

// MARK: - Like button

struct LikeButton: View {
    let trackID: Int
    var size: CGFloat = 13
    var diameter: CGFloat = 32

    @EnvironmentObject private var account: AccountStore

    var body: some View {
        let liked = account.isLiked(trackID)
        PlayerIconButton(
            icon: liked ? "heart.fill" : "heart", size: size, diameter: diameter,
            isActive: liked
        ) {
            Task { await account.toggleLike(trackID: trackID) }
        }
        .help(liked ? String(localized: "取消喜欢") : String(localized: "喜欢"))
        .accessibilityLabel(liked ? "取消喜欢" : "喜欢")
    }
}

// MARK: - Scrubber

struct ScrubberLane: View {
    @EnvironmentObject private var player: PlayerService
    @ObservedObject private var clock = PlayerService.shared.clock
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var fraction: Double {
        guard player.duration > 0 else { return 0 }
        let value = isDragging ? dragProgress : clock.progress
        return min(max(value / player.duration, 0), 1)
    }

    var body: some View {
        track
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Formatters.duration(isDragging ? dragProgress : clock.progress)) / \(Formatters.duration(player.duration))")
        .accessibilityAdjustableAction { direction in
            guard player.duration > 0 else { return }
            switch direction {
            case .increment: player.seek(to: min(player.duration, clock.progress + 5))
            case .decrement: player.seek(to: max(0, clock.progress - 5))
            @unknown default: break
            }
        }
        .onDisappear {
            // Releasing the view mid-drag must also release the audio clock.
            if isDragging {
                isDragging = false
                player.isScrubbing = false
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : .black.opacity(0.15))
                    .frame(height: isHovering || isDragging ? 4 : 3)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: width * fraction, height: isHovering || isDragging ? 4 : 3)
                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: max(0, min(width - thumbDiameter, width * fraction - thumbDiameter / 2)))
                    .opacity(isHovering || isDragging ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if isHovering || isDragging {
                    Text("\(Formatters.duration(isDragging ? dragProgress : clock.progress)) / \(Formatters.duration(player.duration))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 124, height: 26)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: max(4, min(width - 128, width * fraction - 62)), y: -30)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.duration > 0, width > 0 else { return }
                        isDragging = true
                        player.isScrubbing = true
                        dragProgress = min(max(value.location.x / width, 0), 1) * player.duration
                    }
                    .onEnded { _ in
                        guard isDragging else { return }
                        player.seek(to: dragProgress)
                        isDragging = false
                        player.isScrubbing = false
                    }
            )
        }
        .frame(height: 14)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) { isHovering = hovering }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isDragging)
    }

    private var thumbDiameter: CGFloat {
        isDragging ? 12 : (isHovering ? 10 : 8)
    }
}

// MARK: - Inline volume

struct VolumeControl: View {
    var compact = false
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        HStack(spacing: compact ? 2 : 6) {
            Image(systemName: volumeIcon)
                .font(.system(size: compact ? 14 : 16, weight: .medium))
                .frame(width: compact ? 16 : 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.14))
                    Capsule().fill(.primary.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(player.volume))
                }
                .frame(height: 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard geo.size.width > 0 else { return }
                    player.volume = Float(min(max(value.location.x / geo.size.width, 0), 1))
                })
            }
            .frame(width: compact ? 30 : 64, height: 26)
        }
        .help("音量")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int(player.volume * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.volume = min(1, player.volume + 0.05)
            case .decrement: player.volume = max(0, player.volume - 0.05)
            @unknown default: break
            }
        }
    }

    private var volumeIcon: String {
        switch player.volume {
        case 0: return "speaker.slash"
        case ..<0.4: return "speaker.wave.1"
        case ..<0.75: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }
}
