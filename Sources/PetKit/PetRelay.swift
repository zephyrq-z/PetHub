import Foundation

/// 一次「谁开口了」的广播。语义与原来三份 `Bridge.swift` 的联动协议一致：
/// 谁说话所有人都能听见；听不听、接不接由各自的策略决定。
///
/// - `hop`：这是第几跳。用户自己点出来的算 0，接话的人广播 `hop + 1`。
/// - `root`：这条链是谁起的头，一路原样传下去，用来防环。
///
/// 原来的实现走 `DistributedNotificationCenter` 跨进程；四只并进一个进程之后
/// 改成进程内直接分发，跳数和 root 的规则一个字节都没改。
struct PetSpeech: Equatable {
    let from: PetID
    let clipID: Int
    let label: String
    let duration: TimeInterval
    let hop: Int
    let root: PetID

    var summary: String {
        "\(from.title) 句=\(clipID) hop=\(hop) root=\(root.title) 时长=\(String(format: "%.2f", duration))"
    }
}

/// 进程内联动通道。
final class PetRelay {
    var isEnabled = true
    var traceEnabled = false

    private var handlers: [PetID: (PetSpeech) -> Void] = [:]
    private var order: [PetID] = []

    func register(_ id: PetID, _ handler: @escaping (PetSpeech) -> Void) {
        if handlers[id] == nil { order.append(id) }
        handlers[id] = handler
    }

    func unregister(_ id: PetID) {
        handlers.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    /// 广播一次开口。发送者本人不会收到自己的广播。
    func announce(_ speech: PetSpeech) {
        guard isEnabled else {
            trace("联动关闭，\(speech.summary) 不广播")
            return
        }
        trace("广播 \(speech.summary)")
        for id in order where id != speech.from {
            handlers[id]?(speech)
        }
    }

    func trace(_ text: String) {
        guard traceEnabled else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        print("[relay] \(stamp) \(text)")
        fflush(stdout)
    }
}