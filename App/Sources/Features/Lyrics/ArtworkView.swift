import ImageIO
import MemoriseCore
import SwiftUI
import UIKit

/// Decoded, downsampled artwork shared by every `ArtworkView` (PLAN_R10 LA3).
@MainActor
private enum ArtworkCache {
    private static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    static func store(_ image: UIImage, for url: URL) { images.setObject(image, forKey: url as NSURL) }

    /// Fetches and downsamples to `maxPixel` off the main actor. `nil` on any failure.
    nonisolated static func fetch(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A square cover with a rounded clip. A cache hit draws on the first render, so scrolling back never flashes the
/// placeholder.
struct ArtworkView: View {
    let url: String?
    var size: CGFloat = 44

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    private var resolvedURL: URL? { url.flatMap(URL.init(string:)) }

    var body: some View {
        let image = loaded ?? resolvedURL.flatMap { ArtworkCache.image(for: $0) }
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Subject.korean.gradient.opacity(0.35)
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let url = resolvedURL else { loaded = nil; return }
        if let cached = ArtworkCache.image(for: url) { loaded = cached; return }
        loaded = nil
        guard let image = await ArtworkCache.fetch(url, maxPixel: size * displayScale), !Task.isCancelled else { return }
        ArtworkCache.store(image, for: url)
        loaded = image
    }
}

#Preview("Artwork") {
    HStack(spacing: 16) {
        ArtworkView(url: nil)
        ArtworkView(url: nil, size: 56)
    }
    .padding()
}
