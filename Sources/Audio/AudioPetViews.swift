import AppKit

/// 桌宠窗口：不抢焦点、不占 Dock、浮在所有空间上。
final class AudioPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AudioPassiveImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AudioPassiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 语音桌宠的头像 + 字幕视图。鼠标手势和原三个仓库一致：
/// 点一下播一句、拖走换位置、右键弹设置。
final class AudioPetView: NSView {
    weak var owner: AudioPetController?

    let face = AudioPassiveImage()
    let caption = AudioPassiveLabel(labelWithString: "")

    private let faceLayout: AudioFaceLayout
    private let animation: AudioPetAnimation

    private var initialMouse = NSPoint.zero
    private var initialWindow = NSPoint.zero
    private var dragged = false

    private var animationTimer: Timer?
    private var phase = 0.0
    private(set) var speaking = false

    init(frame: NSRect, layout: AudioFaceLayout, animation: AudioPetAnimation, accessibilityLabel: String) {
        self.faceLayout = layout
        self.animation = animation
        super.init(frame: frame)

        wantsLayer = true
        face.imageScaling = .scaleProportionallyUpOrDown
        face.wantsLayer = true
        addSubview(face)

        caption.alignment = .center
        caption.textColor = .white
        caption.maximumNumberOfLines = 2
        caption.lineBreakMode = .byTruncatingTail
        caption.wantsLayer = true
        caption.isHidden = true
        switch animation {
        case .squash:
            caption.font = .systemFont(ofSize: 13, weight: .medium)
            caption.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
            caption.layer?.cornerRadius = 9
        case .tilt:
            caption.font = .systemFont(ofSize: 12, weight: .medium)
            caption.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
            caption.layer?.cornerRadius = 10
        }
        addSubview(caption)

        toolTip = "点击随机播放一句 · 拖动移动 · 右键设置"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        face.frame = NSRect(x: faceLayout.insetX,
                            y: faceLayout.insetY,
                            width: bounds.width - 2 * faceLayout.insetX,
                            height: bounds.height - faceLayout.insetY - faceLayout.captionBand)
        caption.frame = NSRect(x: 3,
                               y: bounds.height - faceLayout.captionBand + 4,
                               width: bounds.width - 6,
                               height: 34)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        initialMouse = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        initialWindow = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let dx = current.x - initialMouse.x
        let dy = current.y - initialMouse.y
        if hypot(dx, dy) > 4 { dragged = true }
        if dragged {
            window?.setFrameOrigin(NSPoint(x: initialWindow.x + dx, y: initialWindow.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { owner?.savePosition() } else { owner?.playNext() }
    }

    override func rightMouseDown(with event: NSEvent) {
        owner?.popUpMenu(from: self, with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        owner?.playNext()
        return true
    }

    /// 说话时的待机动画。薄肌/峰哥竖向压扁，太对了左右摇 + 上浮。
    func animate(_ enabled: Bool) {
        speaking = enabled
        animationTimer?.invalidate()
        animationTimer = nil
        phase = 0
        face.layer?.transform = CATransform3DIdentity
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += (self.animation == .squash ? 0.60 : 0.38)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            switch self.animation {
            case .squash:
                // 压扁到 88%，再回到原高。
                let heightScale = 1.0 - 0.12 * (1.0 - cos(self.phase)) / 2.0
                self.face.layer?.transform = CATransform3DMakeScale(1.0, heightScale, 1.0)
            case .tilt:
                let angle = sin(self.phase) * 0.055
                let cx = self.face.bounds.midX
                let cy = self.face.bounds.midY
                var transform = CATransform3DMakeTranslation(cx, cy, 0)
                transform = CATransform3DRotate(transform, angle, 0, 0, 1)
                transform = CATransform3DTranslate(transform, -cx, -cy + abs(sin(self.phase)) * 3, 0)
                self.face.layer?.transform = transform
            }
            CATransaction.commit()
        }
    }
}