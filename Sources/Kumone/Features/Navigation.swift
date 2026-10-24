import SwiftUI

extension Notification.Name {
    static let showDownloadedMusic = Notification.Name("Kumone.showDownloadedMusic")
}

private struct OpenLoginKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct OpenDestinationKey: EnvironmentKey {
    static let defaultValue: (Destination) -> Void = { _ in }
}

extension EnvironmentValues {
    var openLogin: () -> Void {
        get { self[OpenLoginKey.self] }
        set { self[OpenLoginKey.self] = newValue }
    }

    var openDestination: (Destination) -> Void {
        get { self[OpenDestinationKey.self] }
        set { self[OpenDestinationKey.self] = newValue }
    }
}

struct PlayerChromeModifier: ViewModifier {
    @EnvironmentObject private var player: PlayerService
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .trailing) { rightPanel }
            PlayerBar()
        }
        .animation(AppAnimation.standard, value: player.activePanel)
    }

    @ViewBuilder
    private var rightPanel: some View {
        if let panel = player.activePanel {
            Group {
                switch panel {
                case .lyrics:
                    LyricsPanel()
                case .queue:
                    QueuePanel()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.trailing, 16)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

enum RootPage: String, Identifiable {
    case downloaded
    case home
    case explore
    case fm
    case likedSongs
    case daily
    case created
    case recents
    case collections
    case cloud
    case saved

    var id: String { rawValue }

    static let primaryPages: [RootPage] = [.home, .likedSongs, .daily, .created]
    static let menuPages: [RootPage] = [.explore, .fm, .downloaded, .recents, .collections, .cloud, .saved]

    var requiresLogin: Bool {
        switch self {
        case .home, .explore, .fm, .downloaded: return false
        default: return true
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .home: return "推荐"
        case .likedSongs: return "我喜欢"
        case .daily: return "日推"
        case .created: return "我的歌单"
        case .explore: return "精选"
        case .fm: return "漫游"
        case .downloaded: return "已下载"
        case .recents: return "最近播放"
        case .collections: return "我的收藏"
        case .cloud: return "音乐云盘"
        case .saved: return "收藏的歌单"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .likedSongs: return "heart"
        case .daily: return "calendar"
        case .created: return "music.note.list"
        case .explore: return "square.grid.2x2"
        case .fm: return "wave.3.right.circle"
        case .downloaded: return "arrow.down.circle"
        case .recents: return "clock"
        case .collections: return "star"
        case .cloud: return "icloud"
        case .saved: return "rectangle.stack"
        }
    }

    func togglePin(in pages: inout [RootPage]) {
        guard Self.menuPages.contains(self) else { return }
        if let index = pages.firstIndex(of: self) {
            pages.remove(at: index)
        } else {
            pages.append(self)
        }
    }
}

enum Destination: Hashable {
    case downloaded, downloadTasks
    case playlist(Int)
    case radarPlaylist(Int)
    case album(Int)
    case artist(Int)
    case daily
    case toplists
    case recents
    case collections
    case cloud
    case search(String)
}

extension Array where Element == Destination {
    mutating func appendIfNotCurrent(_ destination: Destination) {
        guard last != destination else { return }
        append(destination)
    }
}

/// Registers all shared navigation destinations on a stack.
struct DestinationsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Destination.self) { destination in
            Group {
                switch destination {
                case .downloaded:
                    DownloadedMusicView()
                case .downloadTasks:
                    DownloadTasksView()
                case .playlist(let id):
                    PlaylistDetailView(playlistID: id)
                case .radarPlaylist(let id):
                    PlaylistDetailView(playlistID: id, recommendationContext: .radar)
                case .album(let id):
                    AlbumDetailView(albumID: id)
                case .artist(let id):
                    ArtistDetailView(artistID: id)
                case .daily:
                    DailySongsView()
                case .toplists:
                    ToplistsView()
                case .recents:
                    RecentsView()
                case .collections:
                    CollectionsView()
                case .cloud:
                    CloudView()
                case .search(let query):
                    SearchView(query: query)
                }
            }
            .playerContentInset()
            .toolbar(removing: .title)
            .navigationBarBackButtonHidden(true)
        }
    }
}

extension View {
    func playerChrome() -> some View {
        modifier(PlayerChromeModifier())
    }

    /// The player is outside navigation, so every destination keeps its full viewport.
    func playerContentInset() -> some View {
        self
    }

    func appDestinations() -> some View {
        modifier(DestinationsModifier())
    }
}

/// A small breathing margin at the end of scrollable content.
struct PlayerClearanceSpacer: View {
    var body: some View {
        Color.clear.frame(
            height: Theme.Layout.playerChromeClearance + Theme.Layout.scrollBreathingMargin
        )
    }
}
