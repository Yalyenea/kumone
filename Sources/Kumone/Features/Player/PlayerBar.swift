import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var settings: SettingsManager
    @State private var narrow = false
    @State private var showMore = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 700 {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        songInfoSection(compact: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        transportControls(compact: true)
                        Button { showMore.toggle() } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 28, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("更多播放选项")
                        .accessibilityLabel("更多播放选项")
                        .popover(isPresented: $showMore, arrowEdge: .top) { moreOptions }
                    }
                    ScrubberLane()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 12) {
                    songInfoSection(compact: false)
                        .frame(width: min(252, proxy.size.width * 0.25), alignment: .leading)
                    centerSection.frame(maxWidth: .infinity)
                    optionsSection(compact: proxy.size.width < 960)
                }
                .padding(.horizontal, 18)
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 700 } action: { narrow = $0 }
        .frame(height: narrow ? 82 : Theme.Layout.playerBarHeight)
        .background(Platform.windowBackgroundColor)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Left: artwork + titles + like

    private func songInfoSection(compact: Bool) -> some View {
        HStack(spacing: 10) {
            artworkButton
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    MarqueeText(text: player.currentTrack?.name ?? String(localized: "未在播放"))
                        .frame(height: 17)
                    if !compact, player.currentTrack?.fee == 1 {
                        VIPBadge()
                    }
                }
                Text(player.currentTrack?.artistNames ?? "Kumone")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact, let track = player.currentTrack {
                LikeButton(trackID: track.id)
            }
        }
    }

    private var artworkButton: some View {
        Button {
            guard player.hasCurrentTrack else { return }
            withAnimation(AppAnimation.smooth) {
                player.showNowPlaying = true
            }
        } label: {
            CachedAsyncImage(url: player.currentTrack?.album.picUrl?.resizedImageURL(128))
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.pressable)
        .noFocusRing()
        .help("打开播放页")
        .accessibilityLabel("打开播放页")
    }

    // MARK: - Queue-order control

    /// The queue-order button's three platform-dependent values. macOS cycles
    /// Cycle through list order, shuffle and AutoMix.

    private var queueOrderIcon: String {
        player.queueOrder.symbolName
    }

    private var queueOrderIsActive: Bool {
        player.queueOrder != .listed
    }

    private var queueOrderHelp: LocalizedStringKey {
        player.queueOrder.controlHelp
    }

    private func cycleQueueOrder() {
        player.cycleQueueOrder()
    }

    // MARK: - Center: transport + scrubber

    private var centerSection: some View {
        VStack(spacing: 3) {
            transportControls(compact: false)
            ScrubberLane()
        }
        .padding(.vertical, 5)
        .opacity(player.hasCurrentTrack ? 1 : 0.5)
    }

    private func transportControls(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if !compact, player.isFMMode {
                PlayerIconButton(icon: "trash", size: 12) {
                    player.fmTrash()
                }
                .help("不喜欢，换一首")
            } else if !compact {
                // AutoMix joins the shuffle cycle when its order setting is enabled.
                PlayerIconButton(
                    icon: queueOrderIcon, size: 12,
                    isActive: queueOrderIsActive,
                    action: cycleQueueOrder
                )
                .help(queueOrderHelp)
            }

            if compact, player.isFMMode {
                PlayerIconButton(icon: "trash", size: 14) { player.fmTrash() }
                    .help("不喜欢，换一首")
                    .accessibilityLabel("不喜欢，换一首")
            } else {
                PlayerIconButton(icon: "backward.fill", size: 14, disabled: player.isFMMode) {
                    player.previous()
                }
                .accessibilityLabel("上一首")
            }

            playPauseButton

            PlayerIconButton(icon: "forward.fill", size: 14) {
                player.next()
            }
            .accessibilityLabel("下一首")

            if !compact, player.isFMMode {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .help("私人漫游中")
            } else if !compact {
                PlayerIconButton(
                    icon: player.repeatMode == .one ? "repeat.1" : "repeat", size: 12,
                    isActive: player.repeatMode != .off
                ) {
                    player.cycleRepeatMode()
                }
                .help("循环模式")
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 30, height: 30)
                if player.isBuffering && player.isPlaying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 2)
        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
    }

    // MARK: - Right: quality / panels / volume

    private func optionsSection(compact: Bool) -> some View {
        HStack(spacing: 4) {
            if !compact, let level = player.servedQuality,
               let quality = AudioQuality(rawValue: level) {
                QualityTag(text: quality.badge)
                    .padding(.trailing, 2)
            } else if !compact, player.unblockSource != nil {
                QualityTag(text: String(localized: "音源"))
                    .padding(.trailing, 2)
                    .help("来自 \(player.unblockSource ?? "")")
            }
            PlayerIconButton(
                icon: "quote.bubble", size: 13,
                isActive: player.activePanel == .lyrics
            ) {
                player.activePanel = player.activePanel == .lyrics ? nil : .lyrics
                showMore = false
            }
            .help("歌词")
            .accessibilityLabel("歌词")
            PlayerIconButton(
                icon: "inset.filled.bottomthird.square", size: 13,
                isActive: settings.showDesktopLyrics
            ) {
                settings.showDesktopLyrics.toggle()
            }
            .help("桌面歌词")
            .accessibilityLabel("桌面歌词")
            PlayerIconButton(
                icon: "list.bullet", size: 13,
                isActive: player.activePanel == .queue,
                disabled: player.isFMMode
            ) {
                player.activePanel = player.activePanel == .queue ? nil : .queue
                showMore = false
            }
            .help("播放队列")
            .accessibilityLabel("播放队列")
            RoutePickerButton(diameter: 26, glyphSize: 13,
                              tint: .secondary, background: .clear)
            VolumeControl()
        }
    }

    private var moreOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("播放选项").font(.headline)
            if let track = player.currentTrack {
                HStack {
                    Text("喜欢这首歌")
                    Spacer()
                    LikeButton(trackID: track.id)
                }
            }
            if !player.isFMMode {
                Button { cycleQueueOrder() } label: {
                    Label(player.queueOrder.menuTitle, systemImage: queueOrderIcon)
                }
                Button { player.cycleRepeatMode() } label: {
                    Label("循环模式", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat")
                }
            }
            Divider()
            optionsSection(compact: false)
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(minWidth: 260)
    }
}

// MARK: - Icon button

/// How the one queue-order control presents each state. Here rather than on
/// the enum itself so `QueueOrder` stays a pure Core type: three transports
/// (this bar, the now-playing page, the Dock menu) read the same two answers.
extension QueueOrder {
    /// `wand.and.stars` for AutoMix: it reads as "smart shuffle" next to the
    /// plain `shuffle` arrows, and the accent tint the button applies to any
    /// non-listed state carries the rest.
    var symbolName: String {
        switch self {
        case .listed, .shuffled: return "shuffle"
        case .autoMix: return "wand.and.stars"
        }
    }

    /// Tooltip / menu wording for the state the control is *in*.
    var controlHelp: LocalizedStringKey {
        switch self {
        case .listed, .shuffled: return "随机播放"
        case .autoMix: return "AutoMix 顺序"
        }
    }

    /// The Dock menu names all three states — it is a list of them rather than
    /// a button standing in one, so `listed` gets a word of its own.
    var menuTitle: String {
        switch self {
        case .listed: return String(localized: "列表顺序")
        case .shuffled: return String(localized: "随机播放")
        case .autoMix: return String(localized: "AutoMix 顺序")
        }
    }
}

struct PlayerIconButton: View {
    let icon: String
    var size: CGFloat = 14
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
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(backgroundColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .onHover { isHovering = $0 }
        .animation(AppAnimation.quick, value: isHovering)
    }

    private var backgroundColor: Color {
        let base: Color = colorScheme == .dark ? .white : .black
        if isHovering, !disabled { return base.opacity(0.08) }
        if isActive { return base.opacity(0.05) }
        return .clear
    }
}

// MARK: - Like button

struct LikeButton: View {
    let trackID: Int
    var size: CGFloat = 13

    @EnvironmentObject private var account: AccountStore

    var body: some View {
        let liked = account.isLiked(trackID)
        PlayerIconButton(
            icon: liked ? "heart.fill" : "heart", size: size,
            isActive: liked
        ) {
            Task { await account.toggleLike(trackID: trackID) }
        }
        .help(liked ? String(localized: "取消喜欢") : String(localized: "喜欢"))
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
        HStack(spacing: 8) {
            timeLabel(isDragging ? dragProgress : clock.progress)
            track
            timeLabel(player.duration)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeLabel(_ value: TimeInterval) -> some View {
        Text(Formatters.duration(value))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34)
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : .black.opacity(0.15))
                    .frame(height: 3.5)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(3.5, width * fraction), height: 3.5)
                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: width * fraction - thumbDiameter / 2)
                    .opacity(isHovering || isDragging ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.duration > 0 else { return }
                        isDragging = true
                        player.isScrubbing = true
                        dragProgress = min(max(value.location.x / width, 0), 1) * player.duration
                    }
                    .onEnded { _ in
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

// MARK: - Volume

struct VolumeControl: View {
    @EnvironmentObject private var player: PlayerService
    @State private var showPopover = false

    var body: some View {
        PlayerIconButton(icon: volumeIcon, size: 13) {
            showPopover.toggle()
        }
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VolumeSlider()
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
        }
        .help("音量")
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

struct VolumeSlider: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : .black.opacity(0.15))
                    .frame(width: 4)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 4, height: max(4, height * CGFloat(player.volume)))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        player.volume = Float(min(max(1 - value.location.y / height, 0), 1))
                    }
            )
        }
        .frame(width: 22, height: 110)
    }
}
