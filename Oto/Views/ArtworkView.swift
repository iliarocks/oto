import SwiftUI

struct ArtworkView: View {
    let key: String?
    let directory: URL
    var size: CGFloat? = nil
    var animatesChanges = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var displayedKey: String?
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay { Image(systemName: "music.note").font(.system(size: (size ?? 180) * 0.3, weight: .light)).foregroundStyle(.secondary) }
                }
            }
            .id(displayedKey)
            .transition(.opacity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: key) {
            let nextImage: UIImage?
            if let key {
                let url = directory.appendingPathComponent(key)
                let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
                guard !Task.isCancelled else { return }
                nextImage = data.flatMap(UIImage.init(data:))
            } else {
                nextImage = nil
            }
            // Keep the previous cover while reading its replacement; never flash
            // a placeholder between two albums. Only playback artwork crossfades.
            let animation: Animation? = animatesChanges && hasLoaded
                ? .easeInOut(duration: reduceMotion ? 0.15 : 0.28) : nil
            withAnimation(animation) {
                image = nextImage
                displayedKey = key
                hasLoaded = true
            }
        }
    }
}
