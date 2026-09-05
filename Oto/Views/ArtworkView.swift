import SwiftUI

struct ArtworkView: View {
    let key: String?
    let directory: URL
    var size: CGFloat? = nil
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "music.note").font(.system(size: (size ?? 180) * 0.3, weight: .light)).foregroundStyle(.secondary) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: key) {
            image = nil
            guard let key else { return }
            let url = directory.appendingPathComponent(key)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}
