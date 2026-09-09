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
            titleProgress = target
            guard animate else { alpha = target; return }
            // Match the backdrop's short easing, while retaining intermediate values on a slow drag.
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.alpha = target
            }
        }
    }
}
