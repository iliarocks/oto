import SwiftUI
import UIKit

struct PlaybackSlider: UIViewRepresentable {
    let player: PlaybackController
    let active: Bool
    @Binding var preview: Double
    @Binding var seeking: Bool
    @Environment(\.albumAccent) private var accent

    func makeUIView(context: Context) -> PlaybackSliderView { PlaybackSliderView() }

    func updateUIView(_ view: PlaybackSliderView, context: Context) {
        view.player = player
        view.active = active
        view.tintColor = UIColor(accent)
        view.maximumValue = Float(max(player.duration, 1))
        view.preview = { preview = $0 }
        view.editing = { seeking = $0 }
        view.refresh()
    }

    static func dismantleUIView(_ view: PlaybackSliderView, coordinator: ()) { view.stopDisplayLink() }
}

final class PlaybackSliderView: UISlider {
    weak var player: PlaybackController?
    var active = false
    var preview: ((Double) -> Void)?
    var editing: ((Bool) -> Void)?
    private var scrubbing = false
    private var seekingTrackID: String?
    private var displayLink: CADisplayLink?

    init() {
        super.init(frame: .zero)
        minimumValue = 0
        isContinuous = true
        accessibilityLabel = "Playback Position"
        accessibilityIdentifier = "playback-position"
        addTarget(self, action: #selector(valueChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        // UISlider rounds its default thumb placement to whole points. Interpolate
        // between its native endpoints to retain sub-point motion and hit geometry.
        var thumb = super.thumbRect(forBounds: bounds, trackRect: rect, value: value)
        let first = super.thumbRect(forBounds: bounds, trackRect: rect, value: minimumValue)
        let last = super.thumbRect(forBounds: bounds, trackRect: rect, value: maximumValue)
        let fraction = CGFloat((value - minimumValue) / max(maximumValue - minimumValue, 1))
        thumb.origin.x = first.midX + (last.midX - first.midX) * fraction - thumb.width / 2
        return thumb
    }

    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }

    func refresh() {
        if !scrubbing { setValue(Float(player?.preciseElapsed ?? 0), animated: false) }
        if active && player?.isPlaying == true && !scrubbing && window != nil {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick(_:)))
            let maximum = Float(window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else { stopDisplayLink() }
    }

    func stopDisplayLink() { displayLink?.invalidate(); displayLink = nil }

    fileprivate func tick() {
        guard !scrubbing, let player else { return }
        setValue(Float(player.preciseElapsed), animated: false)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard player?.isLoading == false, super.beginTracking(touch, with: event) else { return false }
        scrubbing = true
        seekingTrackID = player?.currentTrack?.id
        stopDisplayLink()
        editing?(true)
        preview?(Double(value))
        return true
    }

    @objc private func valueChanged() { if scrubbing { preview?(Double(value)) } }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        finishSeeking()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        finishSeeking()
    }

    private func finishSeeking() {
        guard scrubbing else { return }
        if player?.currentTrack?.id == seekingTrackID { player?.seek(to: Double(value)) }
        scrubbing = false
        editing?(false)
        refresh()
    }

    override var accessibilityValue: String? {
        get { MusicTime.clock(Double(value)) }
        set { }
    }

    override func accessibilityIncrement() { adjustAccessibility(by: 5) }
    override func accessibilityDecrement() { adjustAccessibility(by: -5) }
    private func adjustAccessibility(by delta: Double) {
        guard let player, !player.isLoading else { return }
        player.seek(to: player.preciseElapsed + delta)
        refresh()
    }
}

@MainActor private final class DisplayLinkTarget: NSObject {
    weak var view: PlaybackSliderView?
    init(_ view: PlaybackSliderView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        if let view { view.tick() } else { link.invalidate() }
    }
}
