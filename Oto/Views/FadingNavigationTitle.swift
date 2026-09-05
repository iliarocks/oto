import SwiftUI
import UIKit

/// A persistent native title label avoids toolbar content replacement interrupting fade-out.
struct FadingNavigationTitle: UIViewRepresentable {
    let title: String
    let isVisible: Bool

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
        label.setTitleVisible(isVisible)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TitleLabel, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: size.height)
    }

    final class TitleLabel: UILabel {
        private var titleVisible: Bool?

        func setTitleVisible(_ visible: Bool) {
            isAccessibilityElement = visible
            accessibilityElementsHidden = !visible
            guard titleVisible != visible else { return }
            let animate = titleVisible != nil && window != nil
            titleVisible = visible
            let target: CGFloat = visible ? 1 : 0
            guard animate else { alpha = target; return }
            // Retarget from the visible alpha when a drag reverses during the transition.
            UIView.animate(withDuration: 0.25, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
                self.alpha = target
            }
        }
    }
}
