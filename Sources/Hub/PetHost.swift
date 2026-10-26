import AppKit
import Foundation

/// 素材/播放之类的可展示错误。中文文案直接进弹窗。
struct PetError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 主控（合集 App）暴露给桌宠的能力。桌宠的菜单通过它隐藏自己、查询联动开关。
protocol PetHubContext: AnyObject {
    var relayEnabled: Bool { get }
    func isPetVisible(_ id: PetID) -> Bool
    func hidePet(_ id: PetID)
    func showPet(_ id: PetID)
    func togglePet(_ id: PetID)
    /// 桌宠开口说话时回报给主控，由主控转发到进程内联动通道。
    func forwardSpeech(_ speech: PetSpeech)
    func quitApp()
    /// 「大小联动」总开关：打开时改任意一只的大小会同步到另外三只。
    var linkSizeEnabled: Bool { get }
    func petSizeScaleChanged(_ id: PetID, scale: Double)
    /// 「绑定相对位置」：拖任意语音桌宠时，其余三只按相同增量整体移动。
    var groupDragEnabled: Bool { get }
    func petDragBegan(_ id: PetID)
    func petDragged(_ id: PetID, dx: CGFloat, dy: CGFloat)
    func petDragEnded(_ id: PetID)
}

/// 大小滑块的统一范围：相对每只默认大小的 50%–180%。
enum PetSizing {
    static let minScale = 0.5
    static let maxScale = 1.8
}

/// 合集里的一只桌宠。语音桌宠和果冻都实现这一套接口，主控不关心具体实现。
protocol PetHost: AnyObject {
    var id: PetID { get }
    var isVisible: Bool { get }
    /// 窗口尺寸，主控拿它做布局和自检。
    var panelSize: NSSize { get }
    var context: PetHubContext? { get set }

    /// 建窗口、恢复位置并显示。素材缺失时抛错。
    func start() throws
    func setVisible(_ visible: Bool)
    /// 这一只自己的完整菜单（右键和菜单栏子菜单共用）。
    func makeMenu() -> NSMenu
    /// 移回首次启动那一排里的默认位置。
    func moveToDefaultPosition()
    /// 合集总开关变化。桌宠收到 false 时应取消还没开口的接话。
    func setRelayEnabled(_ enabled: Bool)
    /// 收到合集内另一只桌宠说的话。听不听、接不接由各自策略决定。
    func handleRelay(_ speech: PetSpeech)
    /// 自检。通过调 `report(true, "描述")`，失败调 `report(false, "描述")`。
    func selfTest(_ report: (Bool, String) -> Void)
    func shutdown()
    /// 当前画面离屏渲染，给 `--preview` 和排查用。
    func previewImage() -> NSImage?
    /// 启动时那一句提示字幕。果冻没有字幕，留空实现。
    func showStartupHint()
    /// `--dump-state` 用的一行状态。
    var stateDescription: String { get }
    /// 相对默认大小（1.0 = 默认）的缩放。滑块直接改这个值。
    var sizeScale: Double { get }
    func applySizeScale(_ scale: Double)
    /// 横向可见宽度：语音桌宠是窗口宽，果冻是图标边长。紧凑排列用它算间距。
    var visualWidth: CGFloat { get }
    /// 把这只放到一排里的指定左边界/底边（语音桌宠按窗口原点，果冻按图标中心换算）。
    func moveToRow(left: CGFloat, bottom: CGFloat)
    /// 提到最前（捧哏排列要按前后层次叠放）。
    func bringToFront()
    /// 窗口 frame，复合预览和排查用。
    var windowFrame: NSRect { get }
    /// 绑定相对位置时，按增量整体平移（被拖的那只自己用）。
    func moveBy(dx: CGFloat, dy: CGFloat)
    /// 绑定拖动开始：记下当前位置作为基准，之后用“基准 + 总偏移”绝对定位，
    /// 避免逐步读回被 window server 量化过的 frame 造成累积漂移。
    func beginGroupDrag()
    func setGroupDragOffset(dx: CGFloat, dy: CGFloat)
    func endGroupDrag()
    /// 拖完/需要时落盘位置。
    func persistPosition()
}

extension PetHost {
    /// 给 `--dump-state` 用的一行状态。语音桌宠会覆盖成更详细的一行。
    var stateDescription: String {
        "\(id.rawValue) visible=\(isVisible) size=\(Int(panelSize.width))x\(Int(panelSize.height))"
    }

    func showStartupHint() {}
    var sizeScale: Double { 1.0 }
    func applySizeScale(_ scale: Double) {}
    var visualWidth: CGFloat { panelSize.width }
    func moveToRow(left: CGFloat, bottom: CGFloat) {}
    func bringToFront() {}
    var windowFrame: NSRect { .zero }
    func moveBy(dx: CGFloat, dy: CGFloat) {}
    func beginGroupDrag() {}
    func setGroupDragOffset(dx: CGFloat, dy: CGFloat) {}
    func endGroupDrag() {}
    func persistPosition() {}
}