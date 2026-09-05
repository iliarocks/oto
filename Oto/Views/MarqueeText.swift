import SwiftUI

/// One accessible label, with a seamless repeating copy only when it overflows.
struct MarqueeText: View {
    let text: String
    var alignment: Alignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var textWidth: CGFloat = 0
    @State private var started = Date()

    var body: some View {
        // The hidden label supplies the font's single-line height, not its width.
        Text(text.isEmpty ? " " : text)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay {
                GeometryReader { geometry in
                    let overflows = textWidth > geometry.size.width + 1
                    let moving = overflows && !reduceMotion && scenePhase == .active
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                        let distance = textWidth + 32
                        let period = 1.5 + distance / 26
                        let phase = max(0, timeline.date.timeIntervalSince(started)).truncatingRemainder(dividingBy: max(1, period))
                        let offset = moving ? max(0, phase - 1.5) * 26 : 0
                        HStack(spacing: 32) {
                            Text(text)
                                .fixedSize()
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0; started = Date() }
                            if moving { Text(text).fixedSize() }
                        }
                        .offset(x: -offset)
                        .frame(width: geometry.size.width, height: geometry.size.height,
                               alignment: overflows ? .leading : alignment)
                        .mask {
                            HStack(spacing: 0) {
                                LinearGradient(colors: [offset > 0 ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 8)
                                Rectangle()
                                LinearGradient(colors: [.black, overflows ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 8)
                            }
                        }
                    }
                    .clipped()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isStaticText)
            .onChange(of: text) { _, _ in started = Date() }
            .onChange(of: scenePhase) { _, _ in started = Date() }
    }
}
