import SwiftUI
import UIKit

/// A persistent native title label avoids toolbar content replacement interrupting fade-out.
struct FadingNavigationTitle: UIViewRepresentable {
    let title: String
    let progress: CGFloat

    func makeUIView(context: Context) -> TitleLabel {
        let label = TitleLabel()
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .label
        label.accessibilityTraits = .header
        label.adjustsFontForContentSizeCategory = true
        updateUIView(label, context: context)
        return label
    }

    func updateUIView(_ label: TitleLabel, context: Context) {
        label.text = title
        label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 20
        )
        label.setTitleProgress(progress)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TitleLabel, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: size.height)
    }

    final class TitleLabel: UILabel {
        private var titleProgress: CGFloat?

        func setTitleProgress(_ progress: CGFloat) {
            let target = min(max(progress, 0), 1)
            isAccessibilityElement = target > 0
            accessibilityElementsHidden = target == 0
            guard titleProgress != target else { return }
            let animate = titleProgress != nil && window != nil
            let revealing = target > (titleProgress ?? 0)
            titleProgress = target
            guard animate else { alpha = target; return }
            // Match the backdrop's short easing, while retaining intermediate values on a slow drag.
            UIView.animate(withDuration: 0.18, delay: revealing ? 0.04 : 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.alpha = target
            }
        }
    }
}

/// Both screens use the same material and easing instead of a second, automatic scroll edge.
struct NavigationHeaderBackdrop: View {
    let progress: CGFloat
    let height: CGFloat
    @State private var opacity: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(.bar)
            .opacity(opacity)
            .frame(height: height)
            .offset(y: -height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { opacity = progress }
            .onChange(of: progress) { old, new in
                // Let the title disappear first; on entry, the background leads.
                withAnimation(.easeOut(duration: 0.18).delay(new < old ? 0.04 : 0)) {
                    opacity = new
                }
            }
    }
}

struct FadingHeaderScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
