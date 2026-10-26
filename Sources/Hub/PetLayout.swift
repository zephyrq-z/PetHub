import AppKit

/// 首次启动（以及「全部归位」）时四只桌宠的站位。
///
/// 四个独立 App 原来都把自己放到屏幕右下角，装在一起会完全重叠。合集按
/// 薄肌、太对了、峰哥、果冻的顺序在右下角排成一行，槽位宽度固定，
/// 每只在自己的槽位里居中，改大小也不会互相压住太多。
enum PetLayout {
    static let order: [PetID] = [.shaolan, .sunpet, .fengge, .jelly]
    static let gap: CGFloat = 36
    static let margin: CGFloat = 24

    /// 槽位宽度：按默认大小给足，改大之后允许溢出一点，不挤压邻居。
    static func slotWidth(_ id: PetID) -> CGFloat {
        switch id {
        case .shaolan: return 260
        case .sunpet: return 180
        case .fengge: return 260
        case .jelly: return 128
        }
    }

    static func rowWidth() -> CGFloat {
        order.reduce(0) { $0 + slotWidth($1) } + gap * CGFloat(order.count - 1)
    }

    static func screen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    static func rowLeft(on screen: NSScreen) -> CGFloat {
        let visible = screen.visibleFrame
        return max(visible.minX + margin, visible.maxX - margin - rowWidth())
    }

    /// 某只桌宠槽位中心的横坐标。
    static func slotCenterX(_ id: PetID, on screen: NSScreen) -> CGFloat {
        var x = rowLeft(on: screen)
        for pet in order {
            let width = slotWidth(pet)
            if pet == id { return x + width / 2 }
            x += width + gap
        }
        return screen.visibleFrame.midX
    }

    /// 一排桌宠的底边（像素底，不是图标底）。
    static func bottom(on screen: NSScreen) -> CGFloat {
        screen.visibleFrame.minY + margin
    }

    /// 语音桌宠的窗口原点：窗口底边对齐一排的底边，水平居中在槽位里。
    static func origin(for id: PetID, panelSize: NSSize) -> NSPoint {
        guard let screen = screen() else { return NSPoint(x: 200, y: 200) }
        return NSPoint(x: slotCenterX(id, on: screen) - panelSize.width / 2,
                       y: bottom(on: screen))
    }
}