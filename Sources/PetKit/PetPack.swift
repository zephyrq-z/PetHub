import AppKit
import AVFoundation
import Foundation

/// 一份「桌宠内容包」里的一条语音。
///
/// 文件路径相对包根目录，方便整个文件夹拷来拷去；`label` 是显示在字幕里的中文。
struct PetPackClip: Codable, Equatable {
    var file: String
    var label: String
}

/// `petpack.json` 的结构。见 docs/PETPACK.md。
struct PetPackManifest: Codable, Equatable {
    /// 格式版本。以后加字段时靠它决定怎么读。
    var format: Int
    /// 桌宠名字，例如「我的老师」。
    var name: String
    /// 可选作者署名。
    var author: String?
    /// 头像文件，相对包根目录。
    var avatar: String
    /// 语音列表：文件 + 中文。
    var clips: [PetPackClip]

    static let currentFormat = 1
}

enum PetPackError: LocalizedError {
    case missingPack(String)
    case badManifest(String)
    case unsafePath(String)
    case missingFile(String)
    case badImage(String)
    case badAudio(String)
    case noClips
    case tooManyClips(Int)
    case emptyLabel
    case emptyName
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPack(let path): return "找不到桌宠包：\(path)"
        case .badManifest(let why): return "桌宠包格式不对：\(why)"
        case .unsafePath(let path): return "桌宠包里有不安全的相对路径：\(path)"
        case .missingFile(let path): return "桌宠包缺少文件：\(path)"
        case .badImage(let path): return "头像读不出来：\(path)"
        case .badAudio(let path): return "语音读不出来（支持 wav / m4a / mp3 / aiff）：\(path)"
        case .noClips: return "至少要放一条语音，不然桌宠没话说。"
        case .tooManyClips(let count): return "语音太多了（\(count) 条），上限 200 条。"
        case .emptyLabel: return "每条语音都要配一句中文。"
        case .emptyName: return "给桌宠起个名字吧。"
        case .writeFailed(let why): return "保存桌宠包失败：\(why)"
        }
    }
}

/// 一个已经落到磁盘上的桌宠内容包。
///
/// 目录结构：
/// ```
/// HeadPet/
///   petpack.json
///   avatar.png
///   clips/01.m4a ...
/// ```
final class PetPack {
    let root: URL
    let manifest: PetPackManifest

    init(root: URL, manifest: PetPackManifest) {
        self.root = root
        self.manifest = manifest
    }

    var name: String { manifest.name }
    var avatarURL: URL { root.appendingPathComponent(manifest.avatar) }

    func url(for clip: PetPackClip) -> URL {
        root.appendingPathComponent(clip.file)
    }

    func avatarImage() -> NSImage? {
        guard let image = NSImage(contentsOf: avatarURL), image.size.width > 0 else { return nil }
        return image
    }

    /// 把内容包读成语音引擎用的 `Clip`。id 从 1 开始，跟「挑一句」「轮播内容」的下标无关。
    func clips() throws -> [Clip] {
        var result: [Clip] = []
        for (index, item) in manifest.clips.enumerated() {
            let url = url(for: item)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PetPackError.missingFile(item.file)
            }
            guard let audio = try? AVAudioPlayer(contentsOf: url), audio.duration > 0.1 else {
                throw PetPackError.badAudio(item.file)
            }
            result.append(Clip(id: index + 1,
                               label: item.label,
                               file: item.file,
                               duration: audio.duration,
                               answer: nil,
                               defaultOff: nil))
        }
        guard !result.isEmpty else { throw PetPackError.noClips }
        return result
    }

    /// 内容指纹：内容变了就把旧的轮播勾选/固定句清零，避免 id 对不上。
    var signature: String {
        var parts: [String] = [manifest.name, manifest.avatar, manifest.author ?? ""]
        for clip in manifest.clips {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: clip).path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            parts.append("\(clip.file)|\(clip.label)|\(size)")
        }
        return parts.joined(separator: "\n")
    }

    func validate() throws {
        guard manifest.format == PetPackManifest.currentFormat else {
            throw PetPackError.badManifest("format=\(manifest.format)，当前只支持 \(PetPackManifest.currentFormat)")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetPackError.emptyName
        }
        try PetPack.checkRelative(manifest.avatar)
        guard FileManager.default.fileExists(atPath: avatarURL.path) else {
            throw PetPackError.missingFile(manifest.avatar)
        }
        guard avatarImage() != nil else { throw PetPackError.badImage(manifest.avatar) }

        guard !manifest.clips.isEmpty else { throw PetPackError.noClips }
        guard manifest.clips.count <= 200 else { throw PetPackError.tooManyClips(manifest.clips.count) }
        for item in manifest.clips {
            try PetPack.checkRelative(item.file)
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { throw PetPackError.emptyLabel }
            let url = url(for: item)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PetPackError.missingFile(item.file)
            }
            guard let audio = try? AVAudioPlayer(contentsOf: url), audio.duration > 0.1 else {
                throw PetPackError.badAudio(item.file)
            }
        }
    }

    static func load(from root: URL) throws -> PetPack {
        let manifestURL = root.appendingPathComponent("petpack.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw PetPackError.missingPack(manifestURL.path)
        }
        let manifest: PetPackManifest
        do {
            manifest = try JSONDecoder().decode(PetPackManifest.self, from: data)
        } catch {
            throw PetPackError.badManifest(error.localizedDescription)
        }
        let pack = PetPack(root: root, manifest: manifest)
        try pack.validate()
        return pack
    }

    static func checkRelative(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"),
              !trimmed.split(separator: "/").contains("..") else {
            throw PetPackError.unsafePath(path)
        }
    }

    /// 默认存放位置：`~/Library/Application Support/PetHub/HeadPet`。
    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PetHub", isDirectory: true)
            .appendingPathComponent("HeadPet", isDirectory: true)
    }
}

/// 安装 / 导入 / 删除自定义内容包。
///
/// 安装时会先写临时目录、完整校验通过后再替换正式目录，避免坏包把正在用的桌宠弄没。
final class PetPackStore {
    let baseURL: URL

    init(baseURL: URL = PetPack.defaultStoreURL) {
        self.baseURL = baseURL
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: baseURL.appendingPathComponent("petpack.json").path)
    }

    func current() -> PetPack? {
        try? PetPack.load(from: baseURL)
    }

    /// 用用户选的图片 + 语音 + 中文安装一份自定义内容包。
    @discardableResult
    func install(name: String, avatarURL: URL, clips: [(url: URL, label: String)],
                 author: String? = nil) throws -> PetPack {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw PetPackError.emptyName }
        guard !clips.isEmpty else { throw PetPackError.noClips }
        guard clips.count <= 200 else { throw PetPackError.tooManyClips(clips.count) }

        let fm = FileManager.default
        let parent = baseURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw PetPackError.writeFailed(error.localizedDescription)
        }
        let temp = parent.appendingPathComponent("HeadPet.tmp-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            try fm.createDirectory(at: temp.appendingPathComponent("clips", isDirectory: true),
                                   withIntermediateDirectories: true)

            let avatarName = "avatar." + (avatarURL.pathExtension.isEmpty ? "png" : avatarURL.pathExtension.lowercased())
            try fm.copyItem(at: avatarURL, to: temp.appendingPathComponent(avatarName))

            var manifestClips: [PetPackClip] = []
            for (index, item) in clips.enumerated() {
                let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { throw PetPackError.emptyLabel }
                let ext = item.url.pathExtension.isEmpty ? "m4a" : item.url.pathExtension.lowercased()
                let relative = String(format: "clips/%02d", index + 1) + "." + ext
                try fm.copyItem(at: item.url, to: temp.appendingPathComponent(relative))
                manifestClips.append(PetPackClip(file: relative, label: label))
            }

            let manifest = PetPackManifest(format: PetPackManifest.currentFormat,
                                           name: trimmedName,
                                           author: author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                           avatar: avatarName,
                                           clips: manifestClips)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: temp.appendingPathComponent("petpack.json"))

            // 临时目录也完整校验一遍，坏文件不出现在正式位置。
            _ = try PetPack.load(from: temp)

            let backup = parent.appendingPathComponent("HeadPet.backup-\(UUID().uuidString)")
            if fm.fileExists(atPath: baseURL.path) {
                try fm.moveItem(at: baseURL, to: backup)
            }
            do {
                try fm.moveItem(at: temp, to: baseURL)
                if fm.fileExists(atPath: backup.path) { try? fm.removeItem(at: backup) }
            } catch {
                if fm.fileExists(atPath: backup.path), !fm.fileExists(atPath: baseURL.path) {
                    try? fm.moveItem(at: backup, to: baseURL)
                }
                throw error
            }
        } catch let error as PetPackError {
            try? fm.removeItem(at: temp)
            throw error
        } catch {
            try? fm.removeItem(at: temp)
            throw PetPackError.writeFailed(error.localizedDescription)
        }
        return try PetPack.load(from: baseURL)
    }

    /// 导入一个已经做好的 `petpack.json` 文件夹（开源架构里给别人分发的格式）。
    @discardableResult
    func importPack(from folder: URL) throws -> PetPack {
        let pack = try PetPack.load(from: folder)
        let clips = pack.manifest.clips.map { item -> (url: URL, label: String) in
            (pack.url(for: item), item.label)
        }
        return try install(name: pack.manifest.name,
                           avatarURL: pack.avatarURL,
                           clips: clips,
                           author: pack.manifest.author)
    }

    func remove() throws {
        guard isInstalled else { return }
        do {
            try FileManager.default.removeItem(at: baseURL)
        } catch {
            throw PetPackError.writeFailed(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}