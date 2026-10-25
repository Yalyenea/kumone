import SwiftUI

/// One text layout preserves readable names when a collaboration has many
/// artists. Separate buttons would each compress to a letter or two.
struct ArtistLinks: View {
    let artists: [ArtistRef]
    var font: Font = .system(size: 11.5)
    var color: Color = .secondary
    let onOpenArtist: (Int) -> Void

    private var names: String {
        artists.filter { !$0.name.isEmpty }.map(\.name).joined(separator: " / ")
    }

    private var linkedNames: AttributedString {
        var result = AttributedString()
        for artist in artists where !artist.name.isEmpty {
            if !result.characters.isEmpty { result.append(AttributedString(" / ")) }
            var name = AttributedString(artist.name)
            if artist.id > 0 { name.link = URL(string: "kumone://artist/\(artist.id)") }
            result.append(name)
        }
        return result
    }

    var body: some View {
        Text(linkedNames)
            .font(font)
            .foregroundStyle(color)
            .tint(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(names)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "kumone", url.host == "artist",
                      let id = Int(url.lastPathComponent), id > 0 else { return .discarded }
                onOpenArtist(id)
                return .handled
            })
    }
}
