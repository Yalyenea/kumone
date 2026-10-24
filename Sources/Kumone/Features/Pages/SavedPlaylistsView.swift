import SwiftUI

struct SavedPlaylistsView: View {
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if account.subscribedPlaylists.isEmpty {
                    EmptyStateView(icon: "rectangle.stack", title: "还没有收藏歌单")
                        .frame(minHeight: 300)
                } else {
                    CardGrid {
                        ForEach(account.subscribedPlaylists) { playlist in
                            NavigationLink(value: Destination.playlist(playlist.id)) {
                                CoverCardBody(
                                    coverURL: playlist.coverURL?.resizedImageURL(384),
                                    title: playlist.name,
                                    subtitle: String(localized: "\(playlist.trackCount) 首")
                                )
                            }
                            .buttonStyle(.interactiveCard)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)
                }
                PlayerClearanceSpacer()
            }
            .padding(.top, 12)
        }
        .navigationTitle("收藏的歌单")
    }
}
