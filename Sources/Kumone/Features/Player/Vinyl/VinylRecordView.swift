import SwiftUI

/// A dark pressed record with a clean paper label; lighting lives on the
/// turntable so the reflection stays still while the album artwork rotates.
public struct VinylRecordView: View {
    public let artworkImage: PlatformImage?
    public let size: CGFloat

    public init(artworkImage: PlatformImage?, size: CGFloat = 280) {
        self.artworkImage = artworkImage
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.035))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }

            // Closely spaced, low-contrast grooves retain their texture at
            // small window sizes without competing with the album cover.
            ForEach(0..<42, id: \.self) { index in
                let diameter = size * (0.625 + CGFloat(index) * 0.0085)
                Circle()
                    .stroke(.white.opacity(index % 7 == 0 ? 0.085 : 0.035),
                            lineWidth: index % 7 == 0 ? 0.65 : 0.4)
                    .frame(width: diameter, height: diameter)
            }

            Circle()
                .fill(.black)
                .frame(width: size * 0.618, height: size * 0.618)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.8)
                }

            Group {
                if let artworkImage {
                    Image(platformImage: artworkImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color(white: 0.16)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.14, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .frame(width: size * 0.59, height: size * 0.59)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .frame(width: size + 6, height: size + 6)
    }
}
