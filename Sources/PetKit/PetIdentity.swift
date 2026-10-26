import AppKit
import Foundation

/// 合集里的四只桌宠。
///
/// `rawValue` 同时是偏好键前缀和 `Assets/` 下的素材目录名，改名会丢用户设置。
enum PetID: String, CaseIterable, Codable {
    case shaolan
    case sunpet
    case fengge
    case jelly

    var title: String {
        switch self {
        case .shaolan: return "薄肌"
        case .sunpet: return "太对了"
        case .fengge: return "峰哥"
        case .jelly: return "果冻"
        }
    }

    var fullName: String {
        switch self {
        case .shaolan: return "薄肌桌宠"
        case .sunpet: return "太对了桌宠"
        case .fengge: return "好事桌宠"
        case .jelly: return "果冻桌宠"
        }
    }

    /// `Assets/` 下一层的目录名。
    var assetsFolder: String {
        switch self {
        case .shaolan: return "shaolan"
        case .sunpet: return "sun"
        case .fengge: return "fengge"
        case .jelly: return "jelly"
        }
    }

    /// 三只有原声、走捧哏联动；果冻只有形变。
    var isAudio: Bool { self != .jelly }
}

/// 每只桌宠自己的一份偏好。键名统一带 `pet.<id>.` 前缀，四只互不覆盖。
///
/// 从旧的三份独立 App 升级过来的用户不会自动继承设置：bundle id 变了，
/// 偏好域不同。这是有意的 —— 新 App 的默认布局和旧 App 的单只右下角不一样。
final class PetSettings {
    let pet: PetID
    private let defaults: UserDefaults
    private var prefix: String { "pet.\(pet.rawValue)." }

    init(_ pet: PetID, defaults: UserDefaults = .standard) {
        self.pet = pet
        self.defaults = defaults
    }

    func has(_ key: String) -> Bool {
        defaults.object(forKey: prefix + key) != nil
    }

    func bool(_ key: String, _ fallback: Bool) -> Bool {
        has(key) ? defaults.bool(forKey: prefix + key) : fallback
    }

    func int(_ key: String, _ fallback: Int) -> Int {
        has(key) ? defaults.integer(forKey: prefix + key) : fallback
    }

    func double(_ key: String, _ fallback: Double) -> Double {
        has(key) ? defaults.double(forKey: prefix + key) : fallback
    }

    func float(_ key: String, _ fallback: Float) -> Float {
        has(key) ? defaults.float(forKey: prefix + key) : fallback
    }

    func string(_ key: String, _ fallback: String) -> String {
        defaults.string(forKey: prefix + key) ?? fallback
    }

    /// UserDefaults 的数组读回来是 [Any] 装 NSNumber/String，不能直接 `as? [Int]`。
    func intSet(_ key: String, _ fallback: Set<Int> = []) -> Set<Int> {
        guard let raw = defaults.array(forKey: prefix + key) else { return fallback }
        return Set(raw.compactMap { entry -> Int? in
            if let number = entry as? NSNumber { return number.intValue }
            if let text = entry as? String { return Int(text) }
            return nil
        })
    }

    func set(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: prefix + key)
    }

    func setIntSet(_ value: Set<Int>, _ key: String) {
        defaults.set(value.sorted(), forKey: prefix + key)
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: prefix + key)
    }
}