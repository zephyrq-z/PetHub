import AppKit
import AVFoundation
import Foundation
import IOKit

/// 三只语音桌宠（薄肌 / 太对了 / 峰哥）的通用引擎。
///
/// 三个上游仓库本来就是同一份代码的复制品；合并后差异全部收进
/// `AudioPetProfile`，这里只留一套播放、捧哏、菜单、自检逻辑。
final class AudioPetController: NSObject, PetHost, AVAudioPlayerDelegate {
    // MARK: 身份与依赖

    let profile: AudioPetProfile
    let settings: PetSettings
    weak var context: PetHubContext?

    var id: PetID { profile.id }
    private(set) var isVisible = true

    var panelSize: NSSize {
        if let panel { return panel.frame.size }
        return NSSize(width: size,
                      height: profile.layout.panelHeight(for: size, faceRatio: imageRatio))
    }

    // MARK: 运行状态

    private var panel: AudioPetPanel?
    private var pet: AudioPetView?
    private var player: AVAudioPlayer?
    private var clips: [Clip] = []
    private var bag = ShuffleBag()
    private var lastPlayed: Int?
    private var randomMode = true
    private var pinnedID: Int?
    private var excludedIDs: Set<Int> = []
    private var captionWork: DispatchWorkItem?
    private var volume: Float
    private var size: CGFloat
    private var imageRatio: CGFloat = 1
    private var relayEnabled = true
    /// 太对了自己的捧哏开关（原 SunPet 的 bridgeEnabled），其余两只是恒 true。
    private var bridgeEnabled = true

    // 捧哏预解码
    private var companionPool: [Clip] = []
    private var companionBag: [Clip] = []
    private var companionPlayers: [Int: AVAudioPlayer] = [:]
    private var companionLead: [Int: TimeInterval] = [:]
    private var companionWork: DispatchWorkItem?
    private let companionOverlap: TimeInterval = 0.3

    // 太对了的机身摇晃
    private let motion = MotionClient()
    private var motionEnabled = false
    private var motionStatus = "机身摇晃：未开启"

    private let testing = CommandLine.arguments.contains("--self-test")
    private let tracing = CommandLine.arguments.contains("--trace")
    private let previewing = CommandLine.arguments.contains("--preview")
    private let dumping = CommandLine.arguments.contains("--dump-state")
    private let chainTesting = CommandLine.arguments.contains("--chain-test")
    /// 诊断模式只读：不写偏好、不自动开传感器、不存位置。
    private var diagnostic: Bool { testing || previewing || dumping || chainTesting }

    private var resources: URL { Bundle.main.resourceURL! }

    /// 给主控的「关于」面板用。
    var clipCount: Int { clips.count }
    private var petFolder: URL { resources.appendingPathComponent(id.assetsFolder, isDirectory: true) }

    // MARK: 初始化

    init(profile: AudioPetProfile, settings: PetSettings) {
        self.profile = profile
        self.settings = settings
        self.volume = profile.defaultVolume
        self.size = profile.defaultSize
        super.init()
    }

    // MARK: 生命周期

    func start() throws {
        do {
            let data = try Data(contentsOf: petFolder.appendingPathComponent("clips.json"))
            clips = try JSONDecoder().decode([Clip].self, from: data)
        } catch {
            throw PetError("\(profile.id.fullName)的 clips.json 读不出来：\(error.localizedDescription)")
        }
        guard !clips.isEmpty else { throw PetError("\(profile.id.fullName)的 clips.json 是空的") }
        guard let face = NSImage(contentsOf: petFolder.appendingPathComponent("face.png")),
              face.size.width > 0 else {
            throw PetError("\(profile.id.fullName)缺少 Assets/\(id.assetsFolder)/face.png")
        }
        for clip in clips {
            let url = clipURL(clip)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PetError("\(profile.id.fullName)缺少音频：\(clip.file)")
            }
        }

        imageRatio = face.size.height / face.size.width
        loadPreferences()
        buildPanel(face: face)
        restorePosition()
        panel?.orderFrontRegardless()
        preloadCompanionClips()
        if profile.hasMotion && !diagnostic { startMotion() }
    }

    private func loadPreferences() {
        volume = min(max(settings.float("volume", profile.defaultVolume), 0), 1)
        size = min(max(CGFloat(settings.double("size", Double(profile.defaultSize))),
                       profile.minSize), profile.maxSize)
        randomMode = settings.bool("randomMode", true)
        if settings.has("pinnedID") {
            pinnedID = settings.int("pinnedID", -1)
        }
        if settings.has("excludedIDs") {
            excludedIDs = settings.intSet("excludedIDs")
        } else if profile.initialDefaultOffExclusions {
            // 薄肌第一次运行：按素材里的 defaultOff 标出默认轮播，之后用户怎么改都记住。
            excludedIDs = Set(clips.filter { $0.defaultOff == true }.map(\.id))
            if !diagnostic { settings.setIntSet(excludedIDs, "excludedIDs") }
        }
        if !randomMode && !pinValid() { randomMode = true }
        if settings.has("reactionEnabled") {
            bridgeEnabled = settings.bool("reactionEnabled", true)
        }
    }

    private func buildPanel(face: NSImage) {
        let contentSize = NSSize(width: size,
                                 height: profile.layout.panelHeight(for: size, faceRatio: imageRatio))
        let panel = AudioPetPanel(contentRect: NSRect(origin: .zero, size: contentSize),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.title = id.fullName
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = AudioPetView(frame: NSRect(origin: .zero, size: contentSize),
                                layout: profile.layout,
                                animation: profile.animation,
                                accessibilityLabel: profile.accessibilityLabel)
        view.owner = self
        view.face.image = face
        panel.contentView = view

        self.panel = panel
        self.pet = view
        updateToolTip()
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        guard let panel else { return }
        if visible {
            panel.orderFrontRegardless()
            updateToolTip()
        } else {
            stopPlayback()
            companionWork?.cancel()
            companionWork = nil
            panel.orderOut(nil)
        }
    }

    func shutdown() {
        companionWork?.cancel()
        companionWork = nil
        captionWork?.cancel()
        motion.stop()
        if !testing { savePosition() }
        player?.stop()
        pet?.animate(false)
        panel?.orderOut(nil)
    }

    func setRelayEnabled(_ enabled: Bool) {
        relayEnabled = enabled
        if !enabled {
            companionWork?.cancel()
            companionWork = nil
        }
    }

    // MARK: 位置

    func moveToDefaultPosition() {
        guard let panel else { return }
        panel.setFrameOrigin(PetLayout.origin(for: id, panelSize: panel.frame.size))
    }

    private func restorePosition() {
        guard let panel else { return }
        if settings.has("panelX"), settings.has("panelY") {
            let origin = NSPoint(x: settings.double("panelX", 0), y: settings.double("panelY", 0))
            let rect = NSRect(origin: origin, size: panel.frame.size)
            let onScreen = NSScreen.screens.contains { screen in
                let visible = screen.visibleFrame.intersection(rect)
                return visible.width >= 80 && visible.height >= 80
            }
            if onScreen {
                panel.setFrameOrigin(origin)
                return
            }
        }
        moveToDefaultPosition()
    }

    func savePosition() {
        guard !diagnostic, let panel, isVisible else { return }
        settings.set(Double(panel.frame.origin.x), "panelX")
        settings.set(Double(panel.frame.origin.y), "panelY")
    }

    // MARK: 播放

    private func clipURL(_ clip: Clip) -> URL {
        petFolder.appendingPathComponent("Clips", isDirectory: true).appendingPathComponent(clip.file)
    }

    @objc func playNext() {
        guard isVisible else { return }
        if !randomMode, let pin = pinnedID, let clip = clips.first(where: { $0.id == pin }) {
            play(clip)
            return
        }
        playRandom()
    }

    private func playRandom() {
        let ids = clips.filter { !excludedIDs.contains($0.id) }.map(\.id)
        guard let clipID = bag.next(from: ids), let clip = clips.first(where: { $0.id == clipID }) else { return }
        play(clip)
    }

    private func play(_ clip: Clip, hop: Int = 0, root: PetID? = nil) {
        player?.stop()
        pet?.animate(false)
        do {
            let audio = try AVAudioPlayer(contentsOf: clipURL(clip))
            player = audio
            audio.delegate = self
            audio.volume = volume
            audio.prepareToPlay()
            guard audio.play() else { throw PetError("音频播放失败") }
            lastPlayed = clip.id
            pet?.animate(true)
            showCaption(clip.label, seconds: audio.duration + 0.4)
            traceLog("开口 句=\(clip.id) \(clip.label) hop=\(hop) root=\((root ?? id).title) 时长=\(fmt(audio.duration))")
            if !testing {
                context?.forwardSpeech(PetSpeech(from: id, clipID: clip.id, label: clip.label,
                                                 duration: audio.duration, hop: hop, root: root ?? id))
            }
        } catch {
            pet?.animate(false)
            showCaption("这句暂时无法播放", seconds: 4)
        }
    }

    // MARK: 捧哏联动

    func handleRelay(_ speech: PetSpeech) {
        guard isVisible, relayEnabled, bridgeEnabled, !testing else { return }
        guard profile.reaction(speech) else {
            traceLog("收到 \(speech.summary) — 不接")
            return
        }
        traceLog("收到 \(speech.summary) — 接")
        scheduleCompanion(after: speech.duration, hop: speech.hop, root: speech.root)
    }

    /// 只判断策略，不看开关/可见性。自检和排查用。
    func wouldAccept(_ speech: PetSpeech) -> Bool {
        profile.reaction(speech)
    }

    private func scheduleCompanion(after duration: TimeInterval, hop: Int, root: PetID) {
        guard !testing, relayEnabled else { return }
        // 薄肌 → 太对了 → 峰哥 → 太对了，到这里是第四跳，再往下就多出来了。
        guard hop < 3 else { return }
        companionWork?.cancel()
        guard let clip = takeCompanionClip() else { return }
        let lead = companionLead[clip.id] ?? 0
        // 第二跳（太对了接完轮到峰哥）压紧 0.1 秒，四步连起来才不拖。
        let overlap = hop == 1 ? max(0.05, companionOverlap - 0.1) : companionOverlap
        let delay = max(0.02, duration - overlap - lead)
        traceLog("排接话 hop=\(hop) root=\(root.title) 等=\(fmt(delay)) 句=\(clip.id)")
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.relayEnabled else { return }
            // 自己正说着就不叠上去，这一捧算了。
            guard self.player?.isPlaying != true else { return }
            self.playCompanion(clip, hop: hop + 1, root: root)
        }
        companionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func takeCompanionClip() -> Clip? {
        if companionBag.isEmpty { companionBag = companionPool.shuffled() }
        return companionBag.popLast()
    }

    private func playCompanion(_ clip: Clip, hop: Int, root: PetID) {
        if let ready = companionPlayers[clip.id] {
            player?.stop()
            player = ready
            ready.currentTime = 0
            ready.volume = volume
            if ready.play() {
                lastPlayed = clip.id
                pet?.animate(true)
                showCaption(clip.label, seconds: ready.duration + 0.5)
                traceLog("开口 句=\(clip.id) \(clip.label) hop=\(hop) root=\(root.title) 时长=\(fmt(ready.duration))")
                if !testing {
                    context?.forwardSpeech(PetSpeech(from: id, clipID: clip.id, label: clip.label,
                                                     duration: ready.duration, hop: hop, root: root))
                }
                return
            }
        }
        play(clip, hop: hop, root: root)
    }

    private func preloadCompanionClips() {
        companionPool = profile.companion.clips(from: clips,
                                                excluding: excludedIDs,
                                                respectsExclusions: profile.companionRespectsExclusions)
        companionPlayers.removeAll()
        companionLead.removeAll()
        for clip in companionPool {
            let url = clipURL(clip)
            guard let audio = try? AVAudioPlayer(contentsOf: url) else { continue }
            audio.delegate = self
            audio.volume = volume
            audio.prepareToPlay()
            companionPlayers[clip.id] = audio
            companionLead[clip.id] = leadingSilence(of: url)
        }
    }

    /// 这句音频开头垫了多少静音。阈值按峰值的百分比取，免得把底噪当成人声。
    private func leadingSilence(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.processingFormat.sampleRate
        let want = AVAudioFrameCount(min(file.length, AVAudioFramePosition(rate * 0.6)))
        guard want > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: want) else { return 0 }
        do { try file.read(into: buffer) } catch { return 0 }
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var peak: Float = 0
        for i in 0..<count { peak = max(peak, abs(channel[i])) }
        let threshold = max(0.004, peak * 0.06)
        for i in 0..<count where abs(channel[i]) > threshold {
            return Double(i) / rate
        }
        return 0
    }

    // MARK: 菜单

    private func item(_ title: String, _ action: Selector?, tag: Int = 0) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = tag
        return entry
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // 有自定义视图（大小滑块、轮播复选框），关掉自动启用判定，免得被当成无 action 的禁用项。
        menu.autoenablesItems = false
        let header = item("\(profile.menuHeader) · \(clips.count) 句原声", nil)
        header.isEnabled = false
        menu.addItem(header)
        let hint = item(randomMode ? "点击随机播放 · 一轮内不重复" : "点击播放固定那句", nil)
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        menu.addItem(item("随机说一句", #selector(playNext)))
        let choose = item("挑一句", nil)
        let choices = NSMenu()
        if !randomMode {
            let chooseHint = item("点任意一句＝固定播这句", nil)
            chooseHint.isEnabled = false
            choices.addItem(chooseHint)
            choices.addItem(.separator())
        }
        for clip in clips {
            let entry = item(String(format: "%02d  %@", clip.id, clip.label),
                             #selector(chooseClip(_:)), tag: clip.id)
            if !randomMode && pinnedID == clip.id { entry.state = .on }
            choices.addItem(entry)
        }
        choose.submenu = choices
        menu.addItem(choose)

        let mode = item("播放方式", nil)
        let modes = NSMenu()
        let random = item("随机一句（一轮不重复）", #selector(modeRandom))
        random.state = randomMode ? .on : .off
        modes.addItem(random)
        let fixed = item(modeTitle(), #selector(modeFixed))
        fixed.state = randomMode ? .off : .on
        modes.addItem(fixed)
        mode.submenu = modes
        menu.addItem(mode)

        let filters = item("轮播内容", nil)
        let filterMenu = NSMenu()
        let filterHint = item("取消勾选＝不参与随机播", nil)
        filterHint.isEnabled = false
        filterMenu.addItem(filterHint)
        filterMenu.addItem(.separator())
        // 这里必须是真 NSButton（menuItem.view）：普通菜单项点一下就关菜单，
        // 取消十句得重开十次。
        for clip in clips {
            let box = NSButton(checkboxWithTitle: String(format: "%02d  %@", clip.id, clip.label),
                               target: self, action: #selector(toggleExclusionBox(_:)))
            box.tag = clip.id
            box.state = excludedIDs.contains(clip.id) ? .off : .on
            box.font = .systemFont(ofSize: 12)
            box.sizeToFit()
            let holder = NSMenuItem()
            holder.view = box
            filterMenu.addItem(holder)
        }
        filterMenu.addItem(.separator())
        filterMenu.addItem(item("全部恢复", #selector(enableAllClips)))
        filters.submenu = filterMenu
        menu.addItem(filters)

        menu.addItem(item("停止播放", #selector(stopPlayback)))
        menu.addItem(.separator())

        let relayInfo = item(relayStatusText, nil)
        relayInfo.isEnabled = false
        menu.addItem(relayInfo)
        if profile.showsRelayToggle {
            let toggle = item(bridgeEnabled ? "捧哏联动：开" : "捧哏联动：关", #selector(toggleBridge))
            toggle.state = bridgeEnabled ? .on : .off
            menu.addItem(toggle)
        }

        if profile.hasMotion {
            let motionItem = item(motionEnabled ? "关闭机身摇晃" : "开启机身摇晃", #selector(toggleMotion))
            motionItem.state = motionEnabled ? .on : .off
            menu.addItem(motionItem)
            let motionInfo = item(motionStatus, nil)
            motionInfo.isEnabled = false
            menu.addItem(motionInfo)
        }

        menu.addItem(.separator())
        let volumeItem = item("音量", nil)
        let volumes = NSMenu()
        for value in [0, 25, 50, 65, 80, 100] {
            let option = item(value == 0 ? "静音" : "\(value)%", #selector(setVolume(_:)), tag: value)
            option.state = abs(volume - Float(value) / 100) < 0.01 ? .on : .off
            volumes.addItem(option)
        }
        volumeItem.submenu = volumes
        menu.addItem(volumeItem)

        // 大小滑块直接塞进菜单项视图：拖动时菜单不关，四只可以实时一起变。
        let sizeItem = NSMenuItem()
        sizeItem.view = SizeSliderView(scale: sizeScale) { [weak self] scale in
            self?.changeSizeScale(scale)
        }
        menu.addItem(sizeItem)

        menu.addItem(item("移回屏幕右下角", #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(item("隐藏\(profile.id.title)", #selector(hideSelf)))
        return menu
    }

    private var relayStatusText: String {
        if !relayEnabled { return "联动：已关" }
        if profile.showsRelayToggle && !bridgeEnabled { return "捧哏：已关" }
        return profile.idleRelayStatus
    }

    private func modeTitle() -> String {
        guard !randomMode, let pin = pinnedID,
              let clip = clips.first(where: { $0.id == pin }) else { return "固定播一句" }
        return String(format: "固定播一句（%02d %@）", clip.id, clip.label)
    }

    private func pinValid() -> Bool {
        guard let pin = pinnedID else { return false }
        return clips.contains { $0.id == pin }
    }

    func popUpMenu(from view: NSView, with event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
    }

    @objc private func chooseClip(_ sender: NSMenuItem) {
        guard let clip = clips.first(where: { $0.id == sender.tag }) else { return }
        if !randomMode {
            pinnedID = clip.id
            settings.set(clip.id, "pinnedID")
        }
        play(clip)
    }

    @objc private func modeRandom() { setMode(random: true) }
    @objc private func modeFixed() { setMode(random: false) }

    private func setMode(random: Bool) {
        randomMode = random
        if !random && !pinValid() {
            pinnedID = (clips.first(where: { $0.id == lastPlayed }) ?? clips.first)?.id
        }
        settings.set(random, "randomMode")
        if let pin = pinnedID { settings.set(pin, "pinnedID") }
        updateToolTip()
        if random {
            showCaption("随机播放 · 一轮不重复", seconds: 3)
        } else if let clip = clips.first(where: { $0.id == pinnedID }) {
            showCaption(String(format: "已固定：%02d %@", clip.id, clip.label), seconds: 4)
        }
    }

    /// 菜单里的复选框被点。菜单不会因此关闭，可以连着取消好几句。
    @objc private func toggleExclusionBox(_ sender: NSButton) {
        let clipID = sender.tag
        if excludedIDs.contains(clipID) {
            excludedIDs.remove(clipID)
        } else {
            guard excludedIDs.count < clips.count - 1 else {
                sender.state = .on
                NSSound.beep()
                return
            }
            excludedIDs.insert(clipID)
        }
        settings.setIntSet(excludedIDs, "excludedIDs")
        bag.remaining.removeAll()
    }

    @objc private func enableAllClips() {
        excludedIDs.removeAll()
        settings.setIntSet(excludedIDs, "excludedIDs")
        showCaption("轮播已恢复全部", seconds: 2)
    }

    @objc private func stopPlayback() {
        companionWork?.cancel()
        companionWork = nil
        player?.stop()
        pet?.animate(false)
        captionWork?.cancel()
        pet?.caption.isHidden = true
    }

    @objc private func setVolume(_ sender: NSMenuItem) {
        volume = Float(sender.tag) / 100
        player?.volume = volume
        settings.set(volume, "volume")
    }

    private func changeSizeScale(_ scale: Double) {
        applySizeScale(scale)
        context?.petSizeScaleChanged(id, scale: sizeScale)
    }

    /// 1.0 = 默认大小；滑块范围 50%–180%。
    var sizeScale: Double {
        guard profile.defaultSize > 0 else { return 1 }
        return Double(size / profile.defaultSize)
    }

    /// 主控滑块 / 别的桌宠改了大小后调这里，只应用不回调，避免循环。
    func applySizeScale(_ scale: Double) {
        let clamped = min(max(scale, PetSizing.minScale), PetSizing.maxScale)
        size = profile.defaultSize * CGFloat(clamped)
        if let panel {
            panel.setContentSize(NSSize(width: size,
                                        height: profile.layout.panelHeight(for: size, faceRatio: imageRatio)))
        }
        if !diagnostic { settings.set(Double(size), "size") }
        savePosition()
    }

    var visualWidth: CGFloat { panel?.frame.width ?? panelSize.width }

    func moveToRow(left: CGFloat, bottom: CGFloat) {
        guard let panel else { return }
        panel.setFrameOrigin(NSPoint(x: left, y: bottom))
        if !diagnostic { savePosition() }
    }

    @objc private func resetPosition() {
        moveToDefaultPosition()
        savePosition()
    }

    @objc private func hideSelf() {
        context?.hidePet(id)
    }

    @objc private func toggleBridge() {
        bridgeEnabled.toggle()
        settings.set(bridgeEnabled, "reactionEnabled")
        if !bridgeEnabled {
            companionWork?.cancel()
            companionWork = nil
        }
        showCaption(bridgeEnabled ? "捧哏联动：开" : "捧哏联动：关", seconds: 3)
    }

    private func updateToolTip() {
        pet?.toolTip = randomMode
            ? "点击随机播放一句 · 拖动移动 · 右键设置"
            : "点击播放固定那句 · 拖动移动 · 右键设置"
    }

    // MARK: 字幕

    private func showCaption(_ text: String, seconds: Double) {
        guard let pet else { return }
        captionWork?.cancel()
        pet.caption.stringValue = text
        pet.caption.isHidden = false
        let work = DispatchWorkItem { [weak self] in self?.pet?.caption.isHidden = true }
        captionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: 音频代理

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        pet?.animate(false)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === self.player else { return }
        stopPlayback()
        showCaption("音频读取失败", seconds: 4)
    }

    // MARK: 机身摇晃（仅太对了）

    private func startMotion() {
        motion.onEvent = { [weak self] event in
            guard let self else { return }
            if event == "ready" {
                self.motionStatus = "机身摇晃：已连接"
                self.showCaption("摇一摇，太对了", seconds: 3)
            } else if event == "shake" {
                if self.isVisible && self.player?.isPlaying != true { self.playNext() }
            } else if event.hasPrefix("error:") {
                self.motionEnabled = false
                self.motion.stop()
                self.motionStatus = String(event.dropFirst(6))
                self.showCaption(self.motionStatus, seconds: 6)
            }
        }
        if sensorAvailable() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.toggleMotion()
            }
        }
    }

    @objc private func toggleMotion() {
        guard profile.hasMotion else { return }
        if motionEnabled {
            motion.stop()
            motionEnabled = false
            motionStatus = "机身摇晃：未开启"
            return
        }
        guard sensorAvailable() else {
            showCaption("这台 Mac 没有可用的运动传感器", seconds: 5)
            return
        }
        guard let executable = Bundle.main.executableURL?.path else { return }
        motionEnabled = true
        motionStatus = "机身摇晃：正在连接"
        do {
            try motion.start(executable: executable)
        } catch {
            motionEnabled = false
            motionStatus = error.localizedDescription
            showCaption(motionStatus, seconds: 5)
        }
    }

    // MARK: 预览

    func previewImage() -> NSImage? {
        guard let pet, pet.bounds.width > 2 else { return nil }
        pet.layoutSubtreeIfNeeded()
        guard let rep = pet.bitmapImageRepForCachingDisplay(in: pet.bounds) else { return nil }
        pet.cacheDisplay(in: pet.bounds, to: rep)
        let image = NSImage(size: pet.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: 诊断

    func showStartupHint() {
        guard !testing else { return }
        showCaption(profile.hint, seconds: 5)
    }

    /// 主控自检/布局用：当前窗口 frame。
    var windowFrame: NSRect { panel?.frame ?? .zero }

    /// 自检时把大小/位置拨回出厂默认，只改内存，不写偏好。
    func prepareDefaultLayoutForTesting() {
        size = profile.defaultSize
        if let panel {
            panel.setContentSize(NSSize(width: size,
                                        height: profile.layout.panelHeight(for: size, faceRatio: imageRatio)))
        }
        moveToDefaultPosition()
    }

    /// `--dump-state` 的一行摘要。
    var stateDescription: String {
        let origin = panel?.frame.origin ?? .zero
        let pool = clips.count - excludedIDs.count
        return "\(id.rawValue) visible=\(isVisible) window=\((panel?.isVisible ?? false) ? "on" : "off")"
            + " size=\(Int(panelSize.width))x\(Int(panelSize.height))"
            + " pos=\(Int(origin.x)),\(Int(origin.y)) clips=\(clips.count) pool=\(pool)"
            + " mode=\(randomMode ? "random" : "fixed") pinned=\(pinnedID.map(String.init) ?? "nil")"
            + " volume=\(String(format: "%.2f", volume)) relay=\(relayEnabled ? "on" : "off")"
    }

    /// `--chain-test` 静音用：换成 0 但保留时长/回调，节奏不受影响。
    func silenceForDiagnostics() {
        volume = 0
        player?.volume = 0
        for audio in companionPlayers.values { audio.volume = 0 }
    }

    private func traceLog(_ text: String) {
        guard tracing else { return }
        print("[trace] \(String(format: "%.3f", Date().timeIntervalSince1970)) pet=\(id.rawValue) \(text)")
        fflush(stdout)
    }

    private func fmt(_ value: TimeInterval) -> String { String(format: "%.2f", value) }

    // MARK: 自检

    func selfTest(_ report: (Bool, String) -> Void) {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            report(ok, "\(id.rawValue): \(name)")
            if !ok { failures += 1 }
        }

        check(!clips.isEmpty, "素材里有 \(clips.count) 句")
        for clip in clips {
            do {
                let audio = try AVAudioPlayer(contentsOf: clipURL(clip))
                check(audio.duration > 0.25 && audio.duration < 8,
                      "音频 \(clip.id) 可解码且时长合理（\(fmt(audio.duration))s）")
            } catch {
                check(false, "音频 \(clip.id) 读取失败：\(error.localizedDescription)")
            }
        }
        if let image = NSImage(contentsOf: petFolder.appendingPathComponent("face.png")),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            check(bitmap.hasAlpha && (bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1,
                  "头像有透明底")
        } else {
            check(false, "头像解码失败")
        }
        if let panel {
            check(!panel.isOpaque && panel.backgroundColor == .clear && panel.level == .floating,
                  "窗口透明、浮在最上层")
            check(!panel.canBecomeKey && !panel.canBecomeMain,
                  "不抢键盘焦点")
        } else {
            check(false, "窗口没有建立")
            return
        }

        // 随机池：100 轮里一轮不重复、首尾也不重复。
        var testBag = ShuffleBag()
        let allIDs = clips.map(\.id)
        var previous: Int?
        var randomOK = true
        for _ in 0..<100 {
            var cycle: [Int] = []
            for _ in clips {
                guard let id = testBag.next(from: allIDs) else { randomOK = false; break }
                if clips.count > 1 && previous == id { randomOK = false }
                previous = id
                cycle.append(id)
            }
            if Set(cycle).count != clips.count { randomOK = false }
        }
        check(randomOK, "100 轮随机不重复")

        guard let panel, let pet else { return }
        let savedVolume = volume
        volume = 0
        stopPlayback()
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                      timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                                    timestamp: 0.1, windowNumber: panel.windowNumber, context: nil,
                                    eventNumber: 1, clickCount: 1, pressure: 1)!
        pet.mouseDown(with: down)
        pet.mouseUp(with: up)
        check(player?.isPlaying == true && pet.speaking, "点一下开始播放并动起来")

        let firstPlayer = player
        playNext()
        check(firstPlayer?.isPlaying == false && player?.isPlaying == true,
              "再点一下掐掉上一句、不叠音")

        // 拖动只换位置，不该顺带播一句。
        let beforeDragClip = lastPlayed
        let beforeDragOrigin = panel.frame.origin
        pet.mouseDown(with: down)
        let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 30, y: 20),
                                      modifierFlags: [], timestamp: 0.2, windowNumber: panel.windowNumber,
                                      context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        pet.mouseDragged(with: drag)
        pet.mouseUp(with: drag)
        check(lastPlayed == beforeDragClip && panel.frame.origin != beforeDragOrigin,
              "拖动换位置、不误触播放")
        panel.setFrameOrigin(beforeDragOrigin)

        // 固定模式：每次触发都必须播钉住的那句。
        let savedMode = randomMode
        let savedPin = pinnedID
        let savedExcluded = excludedIDs
        randomMode = false
        pinnedID = clips.count > 2 ? clips[2].id : clips.first?.id
        var pinnedOK = true
        for _ in 0..<6 {
            player?.stop()
            playNext()
            if lastPlayed != pinnedID { pinnedOK = false }
        }
        check(pinnedOK, "固定模式每次都播钉住的那句")

        // 勾掉的句子绝不出现在随机里。
        randomMode = true
        excludedIDs = Set(clips.prefix(2).map(\.id))
        var excludedOK = true
        for _ in 0..<40 {
            player?.stop()
            playNext()
            if let played = lastPlayed, excludedIDs.contains(played) { excludedOK = false }
        }
        check(excludedOK, "勾掉的句子不会出现在随机里")

        randomMode = savedMode
        pinnedID = savedPin
        excludedIDs = savedExcluded

        // 菜单结构。
        let menu = makeMenu()
        let chooseCount = menu.items.first(where: { $0.title == "挑一句" })?.submenu?.items.count ?? -1
        check(chooseCount == clips.count, "挑一句列出全部 \(clips.count) 句")
        let boxes = menu.items.first(where: { $0.title == "轮播内容" })?.submenu?.items
            .compactMap { $0.view as? NSButton } ?? []
        check(boxes.count == clips.count && boxes.allSatisfy { !$0.title.isEmpty && $0.action != nil },
              "轮播内容用真复选框（\(boxes.count) 个）")
        let modeItems = menu.items.first(where: { $0.title == "播放方式" })?.submenu?.items.count ?? -1
        check(modeItems == 2, "播放方式有随机/固定两项")

        // 捧哏预解码与开头静音。
        if !companionPool.isEmpty {
            let missingLead = companionPool.filter { companionLead[$0.id] == nil }
            let badLead = companionPool.contains { clip in
                guard let lead = companionLead[clip.id] else { return true }
                return lead < 0 || lead > clip.duration * 0.6
            }
            check(missingLead.isEmpty && !badLead, "捧哏 \(companionPool.count) 句都量出了开头静音")
            check(companionPlayers.count == companionPool.count,
                  "捧哏 \(companionPlayers.count)/\(companionPool.count) 句预解码")
        }

        // 联动策略：三只各自的规则。
        func speech(_ from: PetID, hop: Int, root: PetID) -> PetSpeech {
            PetSpeech(from: from, clipID: 1, label: "自检", duration: 1.5, hop: hop, root: root)
        }
        switch id {
        case .shaolan:
            check(!wouldAccept(speech(.sunpet, hop: 0, root: .sunpet)), "链头只说不接")
        case .sunpet:
            check(wouldAccept(speech(.shaolan, hop: 0, root: .shaolan)), "接薄肌起头的话")
            check(wouldAccept(speech(.fengge, hop: 2, root: .shaolan)), "接峰哥的第三跳")
            check(!wouldAccept(speech(.shaolan, hop: 3, root: .shaolan)), "hop 3 封顶，不再接")
        case .fengge:
            check(wouldAccept(speech(.sunpet, hop: 1, root: .shaolan)), "只在薄肌起的链里接太对了")
            check(!wouldAccept(speech(.sunpet, hop: 1, root: .fengge)), "太对了自己起头不接")
            check(!wouldAccept(speech(.shaolan, hop: 1, root: .shaolan)), "与薄肌之间没有直连")
        case .jelly:
            break
        }

        if profile.hasMotion {
            var detector = ShakeDetector()
            var idleTriggers = 0
            var shakeTriggers = 0
            for i in 0..<400 {
                if detector.ingest(SIMD3(0, 0, 1), time: Double(i) * 0.01) { idleTriggers += 1 }
            }
            for i in 400..<450 {
                if detector.ingest(SIMD3(sin(Double(i)) * 0.7, 0, 1), time: Double(i) * 0.01) {
                    shakeTriggers += 1
                }
            }
            check(idleTriggers == 0 && shakeTriggers == 1,
                  "摇晃检测：静止 \(idleTriggers) 次、摇晃 \(shakeTriggers) 次")
        }

        stopPlayback()
        check(player?.isPlaying == false && !pet.speaking && pet.caption.isHidden,
              "停止播放清掉声音、动画和字幕")
        volume = savedVolume
        if failures == 0 {
            print("[ok] \(id.rawValue) 自检通过（\(clips.count) 句）")
        }
    }
}