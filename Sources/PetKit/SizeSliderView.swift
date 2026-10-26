import AppKit

/// 菜单里的「大小」滑块。
///
/// NSMenuItem 塞一个真 NSView（和「轮播内容」的复选框同一套做法）：拖动滑块时菜单不会关，
/// 可以实时看到四只一起放大/缩小。
final class SizeSliderView: NSView {
    /// 相对每只默认大小的范围。幅度比原来的「小/中/大」三档宽得多：
    /// 最小 50%、最大 180%。
    static let minScale = 0.5
    static let maxScale = 1.8

    let slider: NSSlider
    private let caption: NSTextField
    private let onChange: (Double) -> Void

    init(scale: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        let clamped = min(max(scale, SizeSliderView.minScale), SizeSliderView.maxScale)
        slider = NSSlider(value: clamped,
                          minValue: SizeSliderView.minScale,
                          maxValue: SizeSliderView.maxScale,
                          target: nil, action: nil)
        caption = NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 48))

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.frame = NSRect(x: 14, y: 22, width: 252, height: 20)

        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 14, y: 3, width: 252, height: 16)

        addSubview(slider)
        addSubview(caption)
        updateCaption(clamped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateCaption(_ value: Double) {
        let percent = Int((value * 100).rounded())
        caption.stringValue = "大小 \(percent)%（50%–180%）"
    }

    @objc private func sliderChanged() {
        updateCaption(slider.doubleValue)
        onChange(slider.doubleValue)
    }

    /// 自检用：设值并走一次真实的 action 路径。
    func applyForTesting(_ scale: Double) {
        slider.doubleValue = scale
        sliderChanged()
    }
}