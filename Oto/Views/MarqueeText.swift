import SwiftUI

struct MarqueeText: View {
    let text: String
    var alignment: Alignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var textWidth: CGFloat = 0

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay {
                GeometryReader { geometry in
                    let overflow = textWidth > geometry.size.width + 1
                    let moving = overflow && !reduceMotion && scenePhase == .active
                    MarqueeLine(text: text, width: geometry.size.width, textWidth: textWidth,
                                alignment: overflow ? .leading : alignment, overflow: overflow, moving: moving)
                        .id(MotionIdentity(text: text, width: geometry.size.width, textWidth: textWidth, moving: moving))
                }
            }
            .background {
                Text(text).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct MotionIdentity: Hashable {
    let text: String
    let width: CGFloat
    let textWidth: CGFloat
    let moving: Bool
}

private struct MarqueeLine: View {
    let text: String
    let width: CGFloat
    let textWidth: CGFloat
    let alignment: Alignment
    let overflow: Bool
    let moving: Bool
    @State private var traveling = false

    var body: some View {
        HStack(spacing: 32) {
            Text(text).fixedSize()
            if moving { Text(text).fixedSize() }
        }
        .compositingGroup()
        .offset(x: traveling ? -(textWidth + 32) : 0)
        .frame(width: width, alignment: alignment)
        .clipped()
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [overflow ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                Rectangle()
                LinearGradient(colors: [.black, overflow ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
            }
        }
        .onAppear {
            guard moving else { return }
            // Animate the transform continuously, rather than rebuilding text at 30 Hz.
            withAnimation(.linear(duration: (textWidth + 32) / 26).delay(1.5).repeatForever(autoreverses: false)) {
                traveling = true
            }
        }
    }
}
