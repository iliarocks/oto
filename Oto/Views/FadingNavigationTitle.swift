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
        func setTitleProgress(_ progress: CGFloat) {
            let target = min(max(progress, 0), 1)
            isAccessibilityElement = target > 0
            accessibilityElementsHidden = target == 0
            // The album header supplies an already-interpolated value for both layers.
            // A second UIKit animation would make the title lag on reversal.
            UIView.performWithoutAnimation { alpha = target }
        }
    }
}

/// One reversible timeline drives both layers, including their slight stagger.
struct AlbumNavigationHeader: AnimatableModifier {
    let title: String
    var progress: CGFloat
    let height: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private var backdropProgress: CGFloat { min(max(progress / 0.88, 0), 1) }
    private var titleProgress: CGFloat { min(max((progress - 0.12) / 0.88, 0), 1) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                NavigationHeaderMaterial(progress: backdropProgress, height: height)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    FadingNavigationTitle(title: title, progress: titleProgress)
                        .accessibilityHidden(titleProgress == 0)
                }
            }
    }
}

private struct NavigationHeaderMaterial: View {
    let progress: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.bar)
            .opacity(progress)
            .frame(height: height)
            .offset(y: -height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The library retains its gradual backdrop reveal using the shared material.
struct NavigationHeaderBackdrop: View {
    let progress: CGFloat
    let height: CGFloat
    @State private var opacity: CGFloat = 0

    var body: some View {
        NavigationHeaderMaterial(progress: opacity, height: height)
            .onAppear { opacity = progress }
            .onChange(of: progress) { old, new in
                // Preserve the library backdrop’s existing short trailing fade.
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
