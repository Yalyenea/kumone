import SwiftUI

/// Links the current track metadata to its artist and album without requiring
/// the immersive presentation to own a second navigation stack.
struct NowPlayingTrackDestinationLinks: View {
    let track: Track
    let font: Font
    let color: Color
    let onOpenDestination: (Destination) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ArtistLinks(artists: track.artists, font: font, color: color) { id in
                onOpenDestination(.artist(id))
            }
            .padding(.vertical, 3)

            if track.album.id > 0, !track.album.name.isEmpty {
                if !track.artistNames.isEmpty {
                    Text(" — ")
                }
                Button {
                    onOpenDestination(.album(track.album.id))
                } label: {
                    Text(track.album.name)
                        .contentShape(Rectangle())
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开专辑：\(track.album.name)")
            }
        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityElement(children: .contain)
    }
}
