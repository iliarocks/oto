import SwiftUI
import UIKit

struct MarqueeText: View {
    let text: String
    var alignment: Alignment = .leading
    var style: UIFont.TextStyle = .body
    var weight: UIFont.Weight = .regular
    var color: UIColor = .label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MarqueeLabel(text: text, centered: alignment == .center, style: style, weight: weight,
                     color: color, moving: !reduceMotion && scenePhase == .active)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct MarqueeLabel: UIViewRepresentable {
    let text: String
    let centered: Bool
    let style: UIFont.TextStyle
    let weight: UIFont.Weight
    let color: UIColor
    let moving: Bool

    func makeUIView(context: Context) -> MarqueeLabelView { MarqueeLabelView() }

    func updateUIView(_ view: MarqueeLabelView, context: Context) {
        let traits = UITraitCollection(preferredContentSizeCategory: context.environment.dynamicTypeSize.contentSizeCategory)
        let preferred = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        let font = UIFont(descriptor: preferred.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]), size: preferred.pointSize)
        view.configure(text: text, font: font, color: color, centered: centered, moving: moving)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarqueeLabelView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.textWidth, height: ceil(uiView.font.lineHeight))
    }
}

final class MarqueeLabelView: UIView {
    private let strip = UIView()
    private let first = UILabel()
    private let second = UILabel()
    private let fade = CAGradientLayer()
    private var text = ""
    private(set) var font = UIFont.preferredFont(forTextStyle: .body)
    private var centered = false
    private var moving = false
    private var previousSize = CGSize.zero
    private var needsMotionLayout = true
    private(set) var textWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        addSubview(strip)
        for label in [first, second] {
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            label.isAccessibilityElement = false
            strip.addSubview(label)
        }
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, color: UIColor, centered: Bool, moving: Bool) {
        if self.text != text || self.font != font || self.centered != centered || self.moving != moving {
            self.text = text; self.font = font; self.centered = centered; self.moving = moving
            textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            for label in [first, second] { label.text = text; label.font = font }
            needsMotionLayout = true
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
        for label in [first, second] { label.textColor = color }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: ceil(font.lineHeight)) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        needsMotionLayout = true
        setNeedsLayout()
        if window == nil { strip.layer.removeAnimation(forKey: "marquee") }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard needsMotionLayout || previousSize != bounds.size else { return }
        needsMotionLayout = false
        previousSize = bounds.size
        strip.layer.removeAnimation(forKey: "marquee")
        let overflow = textWidth > bounds.width + 1
        let cycling = overflow && moving && window != nil
        let distance = textWidth + 32
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.frame = CGRect(x: overflow || !centered ? 0 : (bounds.width - textWidth) / 2,
                             y: 0, width: distance + textWidth, height: bounds.height)
        first.frame = CGRect(x: 0, y: 0, width: textWidth, height: bounds.height)
        second.frame = first.frame.offsetBy(dx: distance, dy: 0)
        second.isHidden = !cycling
        fade.frame = bounds
        let edge = min(8 / max(bounds.width, 1), 0.5)
        fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        layer.mask = overflow ? fade : nil
        CATransaction.commit()
        guard cycling else { return }
        // The render server moves this layer at fractional positions. SwiftUI
        // playback updates never restart it or round its offset to whole points.
        let pause = 1.5, duration = Double(distance) / 26 + pause
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -distance]
        animation.keyTimes = [0, NSNumber(value: pause / duration), 1]
        animation.beginTime = strip.layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.duration = duration
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear)]
        animation.repeatCount = .infinity
        let maximum = Float(window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maximum, preferred: maximum)
        strip.layer.add(animation, forKey: "marquee")
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
