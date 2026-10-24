import SwiftUI

/// 私人漫游 — immersive personal FM page.
struct FMView: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin

    var body: some View {
        ZStack {
            backdrop
            if account.hasAuthCookie {
                content
            } else {
                loginPrompt
            }
        }
        .navigationTitle("漫游")
        .compatHiddenToolbarBackground()
    }

    private var track: Track? {
        player.isFMMode ? player.currentTrack : nil
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Platform.windowBackgroundColor.ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        GeometryReader { geo in
            let coverDimension = max(110, min(260, min(geo.size.width - 48, geo.size.height * 0.38)))
            let spacing: CGFloat = geo.size.height < 520 ? 16 : 24

            // Short windows scroll instead of clipping the playback controls.
            ScrollView {
                VStack(spacing: spacing) {

                    ZStack {
                        if let cover = track?.album.picUrl?.resizedImageURL(768) {
                            CachedAsyncImage(url: cover)
                                .frame(width: coverDimension, height: coverDimension)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.quaternary.opacity(0.4))
                                .frame(width: coverDimension, height: coverDimension)
                                .overlay(
                                    Image(systemName: "wave.3.right.circle")
                                        .font(
                                            .system(
                                                size: max(32, coverDimension * 0.25),
                                                weight: .light
                                            )
                                        )
                                        .foregroundStyle(.tertiary)
                                )
                        }
                    }
                    .scaleEffect(player.isPlaying && player.isFMMode ? 1 : 0.94)
                    .animation(AppAnimation.bouncy, value: player.isPlaying && player.isFMMode)

                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text(track?.name ?? String(localized: "私人漫游"))
                                .font(
                                    .system(
                                        size: geo.size.height < 520 ? 18 : 22,
                                        weight: .bold
                                    )
                                )
                                .lineLimit(1)
                            if track?.fee == 1 {
                                VIPBadge()
                            }
                        }
                        Text(track?.artistNames ?? String(localized: "根据你的口味漫游好音乐"))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 420)

                    if player.isFMMode {
                        controls
                    } else {
                        Button {
                            player.startFM()
                        } label: {
                            Label("开始漫游", systemImage: "wave.3.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(Theme.accentGradient, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }

                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                player.fmTrash()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
            .help("不喜欢，换一首")

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 64, height: 64)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(.pressable)

            Button {
                player.fmNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
            .help("下一首")

            if let track {
                LikeButton(trackID: track.id, size: 16)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
            Text("登录后开启私人漫游")
                .font(.headline)
            Text("网易云会根据你的听歌口味推荐音乐")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("登录") { openLogin() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }
}
