import SwiftUI

/// Text tabs share one quiet baseline across profile and message pages.
struct SocialTabBar<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> LocalizedStringKey
    var count: (Item) -> Int = { _ in 0 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 26) {
                ForEach(items) { item in
                    Button { selection = item } label: {
                        HStack(spacing: 6) {
                            Text(title(item))
                            if count(item) > 0 { UnreadCountBadge(count: count(item)) }
                        }
                        .font(.system(size: 13, weight: selection == item ? .semibold : .medium))
                        .foregroundStyle(selection == item ? .primary : .secondary)
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            if selection == item {
                                Capsule().fill(Theme.accent).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.never)
        .overlay(alignment: .bottom) { Color.primary.opacity(0.08).frame(height: 0.5) }
    }
}

struct SocialFilterButton: View {
    let title: LocalizedStringKey
    let selected: Bool
    var count: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count { Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.primary.opacity(selected ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SocialRefreshButton: View {
    var loading = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveRow)
        .disabled(loading)
        .help("刷新").accessibilityLabel("刷新")
    }
}

struct SocialAvatar: View {
    let user: UserProfile
    var size: CGFloat = 40
    var body: some View {
        CachedAsyncImage(url: user.avatarUrl?.resizedImageURL(Int(size * 2))) {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct SocialResourceLink: View {
    let resource: SocialResource
    let kind: SocialResource.Kind
    @Environment(\.openDestination) private var openDestination
    @State private var isLoading = false

    var body: some View {
        Button {
            switch kind {
            case .playlist: openDestination(.playlist(resource.id))
            case .album: openDestination(.album(resource.id))
            case .song:
                isLoading = true
                Task {
                    defer { isLoading = false }
                    do {
                        let response = try await NeteaseAPI.songDetails(ids: [resource.id])
                        guard let track = response.songs.first else { return }
                        PlayerService.shared.playTrack(track)
                    } catch { ToastCenter.shared.show(error.localizedDescription) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                if resource.imageURL != nil {
                    CachedAsyncImage(url: resource.imageURL).frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: kind == .song ? "music.note" : "rectangle.stack").frame(width: 38, height: 38)
                }
                Text(resource.name ?? String(localized: "分享的音乐")).lineLimit(2)
                Spacer(minLength: 0)
                if isLoading { ProgressView().controlSize(.small) }
                else { Image(systemName: kind == .song ? "play.fill" : "chevron.right").foregroundStyle(.secondary) }
            }
            .font(.system(size: 12.5)).padding(9)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(isLoading)
    }
}

struct SocialTime: View {
    let milliseconds: Double
    var body: some View {
        if milliseconds > 0 {
            Text(Date(timeIntervalSince1970: milliseconds / 1000), format: .dateTime.year().month().day().hour().minute())
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct SocialLoginPrompt: View {
    @Environment(\.openLogin) private var openLogin
    var body: some View {
        VStack(spacing: 14) {
            EmptyStateView(icon: "person.crop.circle", title: "登录后查看个人主页与消息")
                .frame(height: 120)
            Button("登录", action: openLogin).buttonStyle(.borderedProminent).tint(Theme.accent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SocialPageFooter<Item: Identifiable>: View {
    @ObservedObject var model: SocialPageModel<Item>
    var body: some View {
        VStack(spacing: 10) {
            if model.isLoading { ProgressView().controlSize(.small) }
            else if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重试") { Task { await model.loadMore() } }
            } else if model.hasMore {
                Button("加载更多") { Task { await model.loadMore() } }.controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}

struct SocialUserRow: View {
    let user: UserProfile
    @Environment(\.openDestination) private var openDestination
    var body: some View {
        Button { openDestination(.profile(user.userId)) } label: {
            HStack(spacing: 12) {
                SocialAvatar(user: user)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.nickname).font(.system(size: 13, weight: .medium))
                    if let signature = user.signature, !signature.isEmpty {
                        Text(signature).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.interactiveRow)
    }
}
