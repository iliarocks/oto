import UIKit
import XCTest
@testable import Oto

final class PlaybackMotionTests: XCTestCase {
    @MainActor func testNativeSliderKeepsFractionalThumbPositions() {
        let slider = PlaybackSliderView()
        slider.frame = CGRect(x: 0, y: 0, width: 342, height: 44)
        slider.maximumValue = 60
        slider.layoutIfNeeded()
        func x(_ value: Float) -> CGFloat {
            slider.setValue(value, animated: false)
            slider.layoutIfNeeded()
            return slider.thumbRect(forBounds: slider.bounds, trackRect: slider.trackRect(forBounds: slider.bounds), value: value).midX
        }
        let positions = (0..<12).map { x(10 + Float($0) / 60) }
        for (previous, next) in zip(positions, positions.dropFirst()) {
            XCTAssertGreaterThan(next, previous, "Each frame must move the thumb, even by less than a point")
            XCTAssertLessThan(next - previous, 1)
        }
    }

    @MainActor func testUnchangedMarqueeDoesNotRestartAnimation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let view = MarqueeLabelView()
        window.addSubview(view)
        window.isHidden = false
        defer { window.isHidden = true }
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 30)
        let font = UIFont.systemFont(ofSize: 22, weight: .bold)
        let text = "A long title that should keep moving during playback updates"
        view.configure(text: text, font: font, color: .label, centered: true, moving: true)
        view.layoutIfNeeded()
        let layer = view.subviews[0].layer
        let start = layer.animation(forKey: "marquee")?.beginTime
        XCTAssertNotNil(start)
        for _ in 0..<20 {
            view.configure(text: text, font: font, color: .secondaryLabel, centered: true, moving: true)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            XCTAssertEqual(layer.animation(forKey: "marquee")?.beginTime, start)
        }
        view.configure(text: text, font: font, color: .label, centered: true, moving: false)
        view.layoutIfNeeded()
        XCTAssertNil(layer.animation(forKey: "marquee"))
        view.configure(text: "Short", font: font, color: .label, centered: true, moving: true)
        view.layoutIfNeeded()
        XCTAssertNil(layer.animation(forKey: "marquee"))
    }
}
