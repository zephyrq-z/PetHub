import AppKit
import Foundation

/// 一句原声。三个语音仓库的 clips.json 字段不完全一样：
/// 薄肌多了 `answer` / `defaultOff`，太对了多了 `timestamp`。
/// 这里取并集，缺的字段是 nil，Codable 会自动忽略不认识的键。
struct Clip: Codable {
    let id: Int
    let label: String
    let file: String
    let duration: Double
    /// 能不能当捧哏。薄肌的素材里带这个标记。
    let answer: Bool?
    /// 首次启动是否排除出轮播。
    let defaultOff: Bool?
}

/// 一轮内不重复的随机池。存 clip.id 而不是下标：轮播内容可以被勾掉，存下标会错位。
struct ShuffleBag {
    var remaining: [Int] = []
    var last: Int?
    mutating func next(from ids: [Int]) -> Int? {
        guard !ids.isEmpty else { return nil }
        remaining.removeAll { !ids.contains($0) }
        if remaining.isEmpty {
            remaining = ids.shuffled()
            if ids.count > 1, remaining.last == last { remaining.swapToFirst() }
        }
        let value = remaining.removeLast()
        last = value
        return value
    }
}

private extension Array where Element == Int {
    mutating func swapToFirst() {
        guard count > 1 else { return }
        swapAt(0, count - 1)
    }
}

/// 说话时的动画风格。薄肌/峰哥是竖向压扁，太对了是左右摇。
enum AudioPetAnimation {
    case squash
    case tilt
}

/// 头像 + 字幕的布局参数。具体数值见 docs/DESIGN.md 3.2。
struct AudioFaceLayout {
    let insetX: CGFloat
    let insetY: CGFloat
    let captionBand: CGFloat

    func panelHeight(for size: CGFloat, faceRatio: CGFloat) -> CGFloat {
        (size - 2 * insetX) * faceRatio + insetY + captionBand
    }
}

/// 捧哏池怎么挑。
enum CompanionSelection {
    case none
    case all
    case ids(Set<Int>)

    func clips(from all: [Clip], excluding: Set<Int>, respectsExclusions: Bool) -> [Clip] {
        switch self {
        case .none:
            return []
        case .all:
            return respectsExclusions ? all.filter { !excluding.contains($0.id) } : all
        case .ids(let ids):
            return all.filter { ids.contains($0.id) && (!respectsExclusions || !excluding.contains($0.id)) }
        }
    }
}

/// 三只语音桌宠的差异全部收在这里；引擎代码只有一份。
struct AudioPetProfile {
    let id: PetID
    let menuHeader: String
    let defaultSize: CGFloat
    let defaultVolume: Float
    let animation: AudioPetAnimation
    let layout: AudioFaceLayout
    let hint: String
    let accessibilityLabel: String
    let companion: CompanionSelection
    let companionRespectsExclusions: Bool
    let initialDefaultOffExclusions: Bool
    /// 听到别人的话要不要接。hop/root 的语义和原 Bridge.swift 一致。
    let reaction: (PetSpeech) -> Bool
    /// 没有联动对象时的说明文案。
    let idleRelayStatus: String
    /// 太对了原来有一个自己的「捧哏联动」开关，保留。
    let showsRelayToggle: Bool
    /// 太对了的机身摇晃。
    let hasMotion: Bool

    var minSize: CGFloat { defaultSize * PetSizing.minScale }
    var maxSize: CGFloat { defaultSize * PetSizing.maxScale }
}

enum AudioPetProfiles {
    /// 薄肌：链头，只说不接。37 句，默认只开 8 句。
    static let shaolan = AudioPetProfile(
        id: .shaolan,
        menuHeader: "薄肌桌宠",
        defaultSize: 260,
        defaultVolume: 0.65,
        animation: .squash,
        layout: AudioFaceLayout(insetX: 8, insetY: 8, captionBand: 44),
        hint: "点我说一句 · 右键设置",
        accessibilityLabel: "薄肌桌宠，点击随机播放一句，拖动移动，右键设置",
        companion: .none,
        companionRespectsExclusions: false,
        initialDefaultOffExclusions: true,
        reaction: { _ in false },
        idleRelayStatus: "联动：只说不接",
        showsRelayToggle: false,
        hasMotion: false
    )

    /// 太对了：谁说话都接，28 句里挑 6 句短的当捧哏。
    static let sunpet = AudioPetProfile(
        id: .sunpet,
        menuHeader: "孙宇晨 · 太对了",
        defaultSize: 180,
        defaultVolume: 0.65,
        animation: .tilt,
        layout: AudioFaceLayout(insetX: 12, insetY: 12, captionBand: 60),
        hint: "点我一下 · 右键设置",
        accessibilityLabel: "孙宇晨桌宠，点击播放，拖动移动，右键设置",
        companion: .ids([1, 2, 4, 11, 13, 14]),
        companionRespectsExclusions: true,
        initialDefaultOffExclusions: false,
        reaction: { speech in
            (speech.from == .shaolan || speech.from == .fengge) && speech.hop < 3
        },
        idleRelayStatus: "捧哏：就位（峰哥、薄肌）",
        showsRelayToggle: true,
        hasMotion: true
    )

    /// 峰哥：只在薄肌起的链里接太对了的话，接完就断。
    static let fengge = AudioPetProfile(
        id: .fengge,
        menuHeader: "好事桌宠",
        defaultSize: 260,
        defaultVolume: 0.65,
        animation: .squash,
        layout: AudioFaceLayout(insetX: 8, insetY: 8, captionBand: 44),
        hint: "点我说一句 · 右键设置",
        accessibilityLabel: "好事桌宠，点击随机播放一句，拖动移动，右键设置",
        companion: .all,
        companionRespectsExclusions: false,
        initialDefaultOffExclusions: false,
        reaction: { speech in
            speech.from == .sunpet && speech.root == .shaolan && speech.hop < 3
        },
        idleRelayStatus: "联动：接太对了",
        showsRelayToggle: false,
        hasMotion: false
    )

    static func profile(for id: PetID) -> AudioPetProfile? {
        switch id {
        case .shaolan: return shaolan
        case .sunpet: return sunpet
        case .fengge: return fengge
        case .jelly: return nil
        }
    }
}