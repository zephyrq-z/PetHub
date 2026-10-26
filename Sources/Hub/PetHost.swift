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
}

extension PetHost {
    /// 给 `--dump-state` 用的一行状态。语音桌宠会覆盖成更详细的一行。
    var stateDescription: String {
        "\(id.rawValue) visible=\(isVisible) size=\(Int(panelSize.width))x\(Int(panelSize.height))"
    }

    func showStartupHint() {}
}