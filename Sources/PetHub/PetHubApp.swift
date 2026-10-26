import AppKit
import Foundation

/// 合集主控。四只桌宠在同一个进程里，主控负责生命周期、菜单栏、显隐、
/// 进程内联动分发和所有诊断入口。
final class PetHubApp: NSObject, NSApplicationDelegate, PetHubContext {
    private let relay = PetRelay()
    private var pets: [PetID: PetHost] = [:]
    private var statusItem: NSStatusItem?
    private let hubDefaults = UserDefaults.standard

    private(set) var relayEnabled = true
    private(set) var linkSizeEnabled = true
    private(set) var groupDragEnabled = false

    private let testing = CommandLine.arguments.contains("--self-test")
    private let chainTesting = CommandLine.arguments.contains("--chain-test")
    private let tracing = CommandLine.arguments.contains("--trace")
    private let dumping = CommandLine.arguments.contains("--dump-state")
    private let previewPath = PetHubApp.argumentValue(for: "--preview")
    /// 自检/诊断模式只读：不把开关和位置写进偏好。
    private var diagnostic: Bool { testing || chainTesting || dumping || previewPath != nil }

    private var speechLog: [PetSpeech] = []
    private var chainAttempt = 0
    private var groupDragTotal = CGSize.zero
    let petPackStore = PetPackStore()
    private var customHeadEditor: CustomHeadImporterController?

    private var groupDragActive = false

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !testing && !chainTesting && !dumping && previewPath == nil,
           anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }

        relayEnabled = hubDefaults.object(forKey: "hub.relayEnabled") as? Bool ?? true
        linkSizeEnabled = hubDefaults.object(forKey: "hub.linkSize") as? Bool ?? true
        groupDragEnabled = hubDefaults.object(forKey: "hub.groupDrag") as? Bool ?? false
        relay.isEnabled = relayEnabled
        relay.traceEnabled = tracing || chainTesting

        buildPets()
        do {
            for id in PetLayout.order {
                try pets[id]?.start()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "桌宠合集启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        for id in PetLayout.order where id.isAudio {
            relay.register(id) { [weak self] speech in
                self?.pets[id]?.handleRelay(speech)
            }
        }
        for pet in pets.values { pet.setRelayEnabled(relayEnabled) }

        if let previewPath {
            // 等一帧，让窗口完成布局再离屏渲染。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.renderPreviews(to: previewPath)
            }
            return
        }
        if testing {
            runSelfTest()
            return
        }
        if dumping {
            dumpState()
            return
        }
        if chainTesting {
            runChainTest()
            return
        }

        installStatusItem()
        for id in PetLayout.order where id.isAudio {
            pets[id]?.showStartupHint()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for pet in pets.values { pet.shutdown() }
        for id in PetLayout.order where id.isAudio { relay.unregister(id) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != getpid() }
    }

    private func buildPets() {
        for id in PetLayout.order {
            let settings = PetSettings(id)
            if let profile = AudioPetProfiles.profile(for: id) {
                pets[id] = AudioPetController(profile: profile, settings: settings)
            } else {
                pets[id] = JellyPetController(settings: settings)
            }
            pets[id]?.context = self
        }
    }

    // MARK: PetHubContext

    func isPetVisible(_ id: PetID) -> Bool {
        pets[id]?.isVisible ?? false
    }

    func hidePet(_ id: PetID) {
        pets[id]?.setVisible(false)
    }

    func showPet(_ id: PetID) {
        pets[id]?.setVisible(true)
    }

    func togglePet(_ id: PetID) {
        guard let pet = pets[id] else { return }
        pet.setVisible(!pet.isVisible)
    }

    func forwardSpeech(_ speech: PetSpeech) {
        speechLog.append(speech)
        relay.announce(speech)
    }

    func petSizeScaleChanged(_ id: PetID, scale: Double) {
        guard linkSizeEnabled else { return }
        for other in PetLayout.order where other != id {
            pets[other]?.applySizeScale(scale)
        }
    }

    func petDragBegan(_ id: PetID) {
        guard groupDragEnabled else { return }
        groupDragTotal = .zero
        groupDragActive = true
        for other in PetLayout.order where other != id {
            pets[other]?.beginGroupDrag()
        }
    }

    func petDragged(_ id: PetID, dx: CGFloat, dy: CGFloat) {
        guard groupDragEnabled else { return }
        if !groupDragActive { petDragBegan(id) }
        groupDragTotal.width += dx
        groupDragTotal.height += dy
        for other in PetLayout.order where other != id {
            pets[other]?.setGroupDragOffset(dx: groupDragTotal.width, dy: groupDragTotal.height)
        }
    }

    func petDragEnded(_ id: PetID) {
        guard groupDragEnabled else { return }
        for other in PetLayout.order where other != id {
            pets[other]?.endGroupDrag()
        }
        groupDragActive = false
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "桌宠"
        item.button?.toolTip = "桌宠合集 · 点击打开菜单"
        item.button?.target = self
        item.button?.action = #selector(openStatusMenu)
        statusItem = item
    }

    @objc private func openStatusMenu() {
        guard let statusItem else { return }
        statusItem.menu = makeHubMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector?, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private func makeHubMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "桌宠合集 · 四只", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let visibility = NSMenuItem(title: "显示 / 隐藏", action: nil, keyEquivalent: "")
        let visibilityMenu = NSMenu()
        for (index, id) in PetLayout.order.enumerated() {
            let entry = menuItem(pets[id]?.displayTitle ?? id.fullName,
                                 #selector(toggleVisibility(_:)), tag: index)
            entry.state = isPetVisible(id) ? .on : .off
            visibilityMenu.addItem(entry)
        }
        visibility.submenu = visibilityMenu
        menu.addItem(visibility)
        menu.addItem(.separator())

        for id in PetLayout.order {
            let submenu = NSMenuItem(title: pets[id]?.displayTitle ?? id.title,
                                     action: nil, keyEquivalent: "")
            submenu.submenu = pets[id]?.makeMenu() ?? NSMenu()
            menu.addItem(submenu)
        }
        menu.addItem(.separator())

        let customRoot = NSMenuItem(title: "自定义桌宠", action: nil, keyEquivalent: "")
        let customMenu = NSMenu()
        let currentPack = petPackStore.current()
        let currentInfo = NSMenuItem(title: currentPack.map { "当前：\($0.name)（替换薄肌）" }
                                        ?? "当前：原版薄肌",
                                     action: nil, keyEquivalent: "")
        currentInfo.isEnabled = false
        customMenu.addItem(currentInfo)
        customMenu.addItem(menuItem("换成我的角色…（替换薄肌）", #selector(openCustomHeadEditor)))
        customMenu.addItem(menuItem("导入 petpack.json 文件夹…", #selector(importCustomHeadPack)))
        customMenu.addItem(menuItem("打开内容包文件夹", #selector(openCustomHeadFolder)))
        if currentPack != nil {
            customMenu.addItem(menuItem("恢复原版薄肌", #selector(restoreBuiltinHead)))
        }
        customRoot.submenu = customMenu
        menu.addItem(customRoot)
        menu.addItem(.separator())

        let relayItem = menuItem("捧哏联动", #selector(toggleRelaySetting))
        relayItem.state = relayEnabled ? .on : .off
        menu.addItem(relayItem)

        let sizeLink = menuItem("大小联动（改一只，四只一起变）", #selector(toggleSizeLink))
        sizeLink.state = linkSizeEnabled ? .on : .off
        menu.addItem(sizeLink)

        let sizeItem = NSMenuItem()
        sizeItem.view = SizeSliderView(scale: commonScale() ?? 1.0) { [weak self] scale in
            self?.applyGlobalSizeScale(scale)
        }
        menu.addItem(sizeItem)

        menu.addItem(menuItem("全部显示", #selector(showAllPets)))
        menu.addItem(menuItem("全部隐藏", #selector(hideAllPets)))
        menu.addItem(menuItem("全部归位", #selector(resetAllPositions)))
        menu.addItem(menuItem("紧凑排列（一键收拢）", #selector(compactArrange)))
        menu.addItem(menuItem("捧哏排列（合影）", #selector(stageArrange)))
        let bindItem = menuItem("绑定相对位置（拖一只，四只一起动）", #selector(toggleGroupDrag))
        bindItem.state = groupDragEnabled ? .on : .off
        menu.addItem(bindItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("关于桌宠合集", #selector(showAbout)))
        menu.addItem(menuItem("退出桌宠合集", #selector(quitApp)))
        return menu
    }

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        guard PetLayout.order.indices.contains(sender.tag) else { return }
        togglePet(PetLayout.order[sender.tag])
    }

    @objc private func toggleRelaySetting() {
        relayEnabled.toggle()
        relay.isEnabled = relayEnabled
        hubDefaults.set(relayEnabled, forKey: "hub.relayEnabled")
        for pet in pets.values { pet.setRelayEnabled(relayEnabled) }
    }

    @objc private func toggleSizeLink() {
        linkSizeEnabled.toggle()
        hubDefaults.set(linkSizeEnabled, forKey: "hub.linkSize")
    }

    @objc private func toggleGroupDrag() {
        groupDragEnabled.toggle()
        if !diagnostic { hubDefaults.set(groupDragEnabled, forKey: "hub.groupDrag") }
    }

    /// 总菜单的滑块：不分联动开关，直接四只一起设。
    private func applyGlobalSizeScale(_ scale: Double) {
        for pet in pets.values { pet.applySizeScale(scale) }
    }

    /// 四只比例一致时返回该比例，否则 nil（滑块回 100%，拖动即统一）。
    private func commonScale() -> Double? {
        let scales = PetLayout.order.compactMap { pets[$0]?.sizeScale }
        guard let first = scales.first else { return nil }
        return scales.allSatisfy { abs($0 - first) < 0.01 } ? first : nil
    }

    /// 这排桌宠当前所在的屏幕。App 不活跃时 NSScreen.main 可能跳到副屏，
    /// 排列要跟着宠物走，不能凭空换一块屏。
    private func arrangementScreen() -> NSScreen? {
        if let frame = pets[.shaolan]?.windowFrame, frame.width > 0 {
            let target = NSPoint(x: frame.midX, y: frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(target) }) {
                return screen
            }
        }
        return PetLayout.screen()
    }

    /// 一键紧凑排列：间距从 36 收到 6，边距 24 收到 16，贴右下角排一行。
    @objc private func compactArrange() {
        guard let screen = arrangementScreen() else { return }
        let gap: CGFloat = 6
        let margin: CGFloat = 16
        let widths = PetLayout.order.map { pets[$0]?.visualWidth ?? 0 }
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1))
        var x = max(screen.visibleFrame.minX + margin,
                    screen.visibleFrame.maxX - margin - total)
        let bottom = screen.visibleFrame.minY + margin
        for (index, id) in PetLayout.order.enumerated() {
            pets[id]?.moveToRow(left: x, bottom: bottom)
            x += widths[index] + gap
        }
    }

    /// 合影站位：薄肌左、太对了中间抬高、峰哥右、果冻缩到峰哥右肩后。
    @objc private func stageArrange() {
        let scales: [PetID: Double] = [.shaolan: 1.2, .sunpet: 1.4, .fengge: 1.2, .jelly: 0.65]
        for (id, scale) in scales { pets[id]?.applySizeScale(scale) }
        guard let screen = arrangementScreen() else { return }
        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        let base = visible.minY + 36
        let firstWidth = pets[.shaolan]?.visualWidth ?? 0
        let secondWidth = pets[.sunpet]?.visualWidth ?? 0
        let thirdWidth = pets[.fengge]?.visualWidth ?? 0
        let jellySide = pets[.jelly]?.visualWidth ?? 0
        let sceneWidth = firstWidth + gap + secondWidth + gap + thirdWidth
        let left = visible.midX - sceneWidth / 2
        let firstHeight = pets[.shaolan]?.panelSize.height ?? 300
        let raise = max(56, firstHeight * 0.18)

        pets[.shaolan]?.moveToRow(left: left, bottom: base)
        pets[.sunpet]?.moveToRow(left: left + firstWidth + gap, bottom: base + raise)
        pets[.fengge]?.moveToRow(left: left + firstWidth + gap + secondWidth + gap, bottom: base)

        let fenggeHeight = pets[.fengge]?.panelSize.height ?? 300
        let jellyCenterX = left + firstWidth + gap + secondWidth + gap + thirdWidth - jellySide * 0.55
        let jellyCenterY = base + fenggeHeight * 0.68
        pets[.jelly]?.moveToRow(left: jellyCenterX - jellySide / 2,
                                bottom: jellyCenterY - jellySide / 2)

        // 后放的在上层：果冻在最后，薄肌在最前，和合影的前后关系一致。
        for id in [PetID.jelly, .sunpet, .fengge, .shaolan] where isPetVisible(id) {
            pets[id]?.bringToFront()
        }
        // 合影站好之后默认绑定相对位置：拖任意一只，四只保持队形整体走。
        groupDragEnabled = true
        if !diagnostic { hubDefaults.set(true, forKey: "hub.groupDrag") }
    }

    @objc private func showAllPets() {
        for pet in pets.values { pet.setVisible(true) }
    }

    @objc private func hideAllPets() {
        for pet in pets.values { pet.setVisible(false) }
    }

    @objc private func resetAllPositions() {
        for pet in pets.values { pet.moveToDefaultPosition() }
    }

    @objc private func openCustomHeadEditor() {
        let editor = CustomHeadImporterController(
            store: petPackStore,
            current: petPackStore.current(),
            onApply: { [weak self] in self?.reloadHeadPet() },
            onRestore: { [weak self] in self?.reloadHeadPet() })
        customHeadEditor = editor
        editor.show()
    }

    @objc private func importCustomHeadPack() {
        let panel = NSOpenPanel()
        panel.title = "选择包含 petpack.json 的文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            _ = try petPackStore.importPack(from: folder)
            reloadHeadPet()
        } catch {
            showAlert("导入桌宠包失败", error.localizedDescription)
        }
    }

    @objc private func openCustomHeadFolder() {
        let folder = PetPack.defaultStoreURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func restoreBuiltinHead() {
        let alert = NSAlert()
        alert.messageText = "恢复原版薄肌？"
        alert.informativeText = "会删掉当前自定义内容包，薄肌恢复成原来的 37 句。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try petPackStore.remove()
            reloadHeadPet()
        } catch {
            showAlert("恢复失败", error.localizedDescription)
        }
    }

    private func reloadHeadPet() {
        guard let audio = pets[.shaolan] as? AudioPetController else { return }
        do {
            try audio.reloadContent()
        } catch {
            showAlert("切换自定义桌宠失败", error.localizedDescription)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func showAbout() {
        let counts = PetLayout.order.compactMap { id -> String? in
            guard let audio = pets[id] as? AudioPetController else { return nil }
            return "\(self.pets[id]?.displayTitle ?? id.title) \(audio.clipCount) 句"
        }.joined(separator: " · ")
        let customLine: String
        if let pack = petPackStore.current() {
            customLine = "\n薄肌槽位当前使用自定义内容：\(pack.name)（\(pack.manifest.clips.count) 句）"
        } else {
            customLine = ""
        }
        let alert = NSAlert()
        alert.messageText = "桌宠合集 2.0.0"
        alert.informativeText = """
        薄肌 · 太对了 · 峰哥 · 果冻，四只桌宠住在同一个 App 里。
        \(counts)\(customLine)

        四个项目分别来自：
        github.com/Ganzhe2028/ShaolanPet
        github.com/Ganzhe2028/SunPet
        github.com/Ganzhe2028/FengGe-Desktop-Pet
        github.com/aurelius358/JellyPet

        代码 MIT。音频和头像版权归原权利人，只做学习交流和玩梗，不商用。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: 诊断入口

    private static func argumentValue(for flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private func dumpState() {
        print("version=2.0.0 relay=\(relayEnabled ? "on" : "off") pets=\(pets.count)")
        for id in PetLayout.order {
            print(pets[id]?.stateDescription ?? "\(id.rawValue) missing")
        }
        fflush(stdout)
        exit(0)
    }

    private func renderPreviews(to directory: String) {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("FAIL 预览目录建不了：\(error.localizedDescription)")
            exit(1)
        }
        var rendered: [(PetID, NSImage)] = []
        for id in PetLayout.order {
            guard let image = pets[id]?.previewImage() else {
                print("FAIL \(id.title) 渲染失败")
                exit(1)
            }
            if writePNG(image, to: folder.appendingPathComponent("preview-\(id.rawValue).png")) {
                print("preview \(folder.appendingPathComponent("preview-\(id.rawValue).png").path)")
                rendered.append((id, image))
            }
        }
        let composite = makeComposite(rendered)
        _ = writePNG(composite, to: folder.appendingPathComponent("preview-all.png"))
        print("preview \(folder.appendingPathComponent("preview-all.png").path)")
        if let stage = makeStageComposite() {
            _ = writePNG(stage, to: folder.appendingPathComponent("preview-stage.png"))
            print("preview \(folder.appendingPathComponent("preview-stage.png").path)")
        }
        fflush(stdout)
        exit(0)
    }

    /// 可见区域：果冻按 128 左右的图标算，语音桌宠按整个窗口算。
    private func visibleFrameFor(_ id: PetID) -> NSRect {
        if let jelly = pets[id] as? JellyPetController {
            let side = jelly.iconSide
            return NSRect(x: jelly.center.x - side / 2, y: jelly.center.y - side / 2,
                          width: side, height: side)
        }
        return pets[id]?.windowFrame ?? .zero
    }

    /// 按合影站位离屏渲染一张合影，用来验证新排列的层次和留白。
    private func makeStageComposite() -> NSImage? {
        stageArrange()
        let stageOrder: [PetID] = [.jelly, .sunpet, .fengge, .shaolan]
        let entries: [(NSImage, NSRect)] = stageOrder.compactMap { id in
            guard let image = pets[id]?.previewImage() else { return nil }
            return (image, pets[id]?.windowFrame ?? .zero)
        }
        guard entries.count == PetLayout.order.count else { return nil }

        var bounds = visibleFrameFor(PetLayout.order[0])
        for id in PetLayout.order.dropFirst() {
            bounds = bounds.union(visibleFrameFor(id))
        }
        bounds = bounds.insetBy(dx: -30, dy: -30)
        let canvasSize = NSSize(width: 1440, height: 720)
        let scale = min(canvasSize.width / bounds.width, canvasSize.height / bounds.height)
        let offset = NSPoint(x: (canvasSize.width - bounds.width * scale) / 2,
                             y: (canvasSize.height - bounds.height * scale) / 2)

        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -90)
        for (image, frame) in entries {
            let rect = NSRect(x: offset.x + (frame.minX - bounds.minX) * scale,
                              y: offset.y + (frame.minY - bounds.minY) * scale,
                              width: frame.width * scale,
                              height: frame.height * scale)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        canvas.unlockFocus()
        return canvas
    }

    private func writePNG(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    /// 四只排一排的合影，方便快速肉眼验收。
    private func makeComposite(_ images: [(PetID, NSImage)]) -> NSImage {
        let canvasSize = NSSize(width: 1440, height: 640)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -90)

        let totalWidth = images.reduce(CGFloat(0)) { $0 + $1.1.size.width } + CGFloat(max(0, images.count - 1)) * 56
        var x = (canvasSize.width - totalWidth) / 2
        for (id, image) in images {
            let size = image.size
            let y = (canvasSize.height - size.height) / 2 + 30
            image.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
            let title = (pets[id]?.displayTitle ?? id.title) as NSString
            let titleSize = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: x + (size.width - titleSize.width) / 2, y: 56), withAttributes: attributes)
            x += size.width + 56
        }
        canvas.unlockFocus()
        return canvas
    }

    // MARK: 自检

    private func runSelfTest() {
        print("== 桌宠合集自检 ==")
        var failures: [String] = []
        var checks = 0
        func check(_ ok: Bool, _ name: String) {
            checks += 1
            print("\(ok ? "OK" : "FAIL") \(name)")
            if !ok { failures.append(name) }
        }
        func visibleFrame(of id: PetID) -> NSRect? {
            if let audio = pets[id] as? AudioPetController {
                return audio.windowFrame
            }
            if let jelly = pets[id] as? JellyPetController {
                let side = jelly.iconSide
                return NSRect(x: jelly.center.x - side / 2, y: jelly.center.y - side / 2,
                              width: side, height: side)
            }
            return nil
        }

        check(pets.count == PetLayout.order.count, "四只桌宠都建好了（\(pets.count) 只）")
        selfTestPetPack(check)
        check(relayEnabled, "联动默认开启")
        for id in PetLayout.order {
            check(pets[id] != nil, "\(id.title) 控制器存在")
        }

        // 通道机制：广播不给发送者，关掉后不广播。
        let probe = PetRelay()
        var delivered: [PetID] = []
        for id in PetLayout.order where id.isAudio {
            probe.register(id) { _ in delivered.append(id) }
        }
        let sample = PetSpeech(from: .shaolan, clipID: 1, label: "自检", duration: 1.2, hop: 0, root: .shaolan)
        probe.announce(sample)
        check(delivered == [.sunpet, .fengge] || delivered == [.fengge, .sunpet],
              "广播发给其他两只、不回给自己")
        check(probe.isEnabled, "通道默认开启")
        delivered.removeAll()
        probe.isEnabled = false
        probe.announce(sample)
        check(delivered.isEmpty, "通道关闭后不广播")

        // 四步链的拓扑：用每只自己的 reaction 策略拼一遍。
        if let shaolan = pets[.shaolan] as? AudioPetController,
           let sunpet = pets[.sunpet] as? AudioPetController,
           let fengge = pets[.fengge] as? AudioPetController {
            let first = PetSpeech(from: .shaolan, clipID: 1, label: "薄肌", duration: 1.0, hop: 0, root: .shaolan)
            let second = PetSpeech(from: .sunpet, clipID: 1, label: "太对了", duration: 1.0, hop: 1, root: .shaolan)
            let third = PetSpeech(from: .fengge, clipID: 1, label: "峰哥", duration: 1.0, hop: 2, root: .shaolan)
            let fourth = PetSpeech(from: .sunpet, clipID: 1, label: "太对了", duration: 1.0, hop: 3, root: .shaolan)
            check(!shaolan.wouldAccept(first), "薄肌不接自己的话")
            check(sunpet.wouldAccept(first), "太对了接薄肌")
            check(fengge.wouldAccept(second), "峰哥接太对了（薄肌起的头）")
            check(sunpet.wouldAccept(third), "太对了接峰哥的第三跳")
            check(!fengge.wouldAccept(fourth), "峰哥不再接第四跳，链在四步收住")
        } else {
            check(false, "三只语音桌宠类型不对")
        }

        // 各只自己的自检（素材、播放、菜单、捧哏预解码、摇晃检测……）。
        for id in PetLayout.order {
            pets[id]?.selfTest(check)
        }

        // 菜单与显隐。
        for id in PetLayout.order {
            let menu = pets[id]?.makeMenu()
            check((menu?.items.count ?? 0) >= 4, "\(id.title) 右键菜单至少 4 项")
            check(menu?.items.contains { $0.title.hasPrefix("隐藏") } == true, "\(id.title) 菜单里有隐藏")
        }
        let hubMenu = makeHubMenu()
        check(hubMenu.items.count >= 10, "菜单栏菜单结构完整（\(hubMenu.items.count) 项）")
        check(setOfVisibilityStates().count == 1, "四只默认都可见")

        // 大小滑块：总菜单滑一次四只一起变；单只菜单的滑块受「大小联动」控制。
        let savedLink = linkSizeEnabled
        linkSizeEnabled = true
        for pet in pets.values { pet.applySizeScale(1.0) }

        if let hubSlider = hubMenu.items.compactMap({ $0.view as? SizeSliderView }).first {
            hubSlider.applyForTesting(1.6)
            check(PetLayout.order.allSatisfy { abs((pets[$0]?.sizeScale ?? 0) - 1.6) < 0.02 },
                  "总菜单大小滑块：四只一起到 160%")
        } else {
            check(false, "总菜单里找不到大小滑块")
        }
        if let audioMenu = pets[.shaolan]?.makeMenu(),
           let petSlider = audioMenu.items.compactMap({ $0.view as? SizeSliderView }).first {
            petSlider.applyForTesting(0.7)
            check(PetLayout.order.allSatisfy { abs((pets[$0]?.sizeScale ?? 0) - 0.7) < 0.02 },
                  "薄肌菜单滑块：联动开，四只一起到 70%")
        } else {
            check(false, "薄肌菜单里找不到大小滑块")
        }
        linkSizeEnabled = false
        if let audioMenu = pets[.shaolan]?.makeMenu(),
           let petSlider = audioMenu.items.compactMap({ $0.view as? SizeSliderView }).first {
            petSlider.applyForTesting(1.4)
            check(abs((pets[.shaolan]?.sizeScale ?? 0) - 1.4) < 0.02
                  && abs((pets[.sunpet]?.sizeScale ?? 0) - 0.7) < 0.02,
                  "关掉大小联动后只改自己")
        }
        linkSizeEnabled = savedLink
        for pet in pets.values { pet.applySizeScale(1.0) }

        // 紧凑排列：一键收拢（间距 6、边距 16），在屏内且不重叠。
        for pet in pets.values { pet.moveToDefaultPosition() }
        if let compact = makeHubMenu().items.first(where: { $0.title == "紧凑排列（一键收拢）" }),
           let action = compact.action {
            NSApp.sendAction(action, to: compact.target, from: compact)
            var compactFrames: [PetID: NSRect] = [:]
            for id in PetLayout.order { compactFrames[id] = visibleFrame(of: id) }
            if let screen = PetLayout.screen() {
                let bottom = screen.visibleFrame.minY + 16
                check(compactFrames.count == PetLayout.order.count
                      && compactFrames.values.allSatisfy { abs($0.minY - bottom) < 1.5 },
                      "紧凑排列：四只底边对齐")
                check(compactFrames.values.allSatisfy { screen.visibleFrame.contains($0) },
                      "紧凑排列：四只都在屏幕可见区")
                var overlap = false
                for (index, first) in PetLayout.order.enumerated() {
                    for second in PetLayout.order.dropFirst(index + 1) {
                        if let a = compactFrames[first], let b = compactFrames[second], a.intersects(b) {
                            overlap = true
                        }
                    }
                }
                check(!overlap, "紧凑排列：四只互不重叠")
                if let a = compactFrames[.shaolan], let b = compactFrames[.sunpet] {
                    check(abs((b.minX - a.maxX) - 6) < 1.5, "紧凑排列：语音窗口间距 6pt")
                }
                if let a = compactFrames[.fengge], let b = compactFrames[.jelly] {
                    check(abs((b.minX - a.maxX) - 6) < 1.5, "紧凑排列：峰哥与果冻图标间距 6pt")
                }
            }
        } else {
            check(false, "菜单里找不到紧凑排列")
        }
        for pet in pets.values { pet.moveToDefaultPosition() }

        // 捧哏排列：按合影站位叠放（太对了抬高、果冻缩到峰哥右肩后）。
        for pet in pets.values { pet.applySizeScale(1.0) }
        if let stage = makeHubMenu().items.first(where: { $0.title == "捧哏排列（合影）" }),
           let action = stage.action {
            NSApp.sendAction(action, to: stage.target, from: stage)
            let expected: [PetID: Double] = [.shaolan: 1.2, .sunpet: 1.4, .fengge: 1.2, .jelly: 0.65]
            check(PetLayout.order.allSatisfy { abs((pets[$0]?.sizeScale ?? 0) - (expected[$0] ?? 0)) < 0.03 },
                  "捧哏排列：四只切到合影比例")
            if let a = visibleFrame(of: .shaolan),
               let b = visibleFrame(of: .sunpet),
               let c = visibleFrame(of: .fengge),
               let d = visibleFrame(of: .jelly),
               let screen = PetLayout.screen() {
                check(b.minY > a.minY + 40, "捧哏排列：太对了抬到高位")
                check(a.maxX <= b.minX + 1 && b.maxX <= c.minX + 1,
                      "捧哏排列：薄肌 → 太对了 → 峰哥 从左到右")
                check(d.intersects(c), "捧哏排列：果冻缩在峰哥右肩后")
                check([a, b, c, d].allSatisfy { screen.visibleFrame.contains($0) },
                      "捧哏排列：四只都在屏幕内")
            }
        } else {
            check(false, "菜单里找不到捧哏排列")
        }
        check(groupDragEnabled, "捧哏排列后自动绑定相对位置")

        // 绑定相对位置：拖一只，其余三只按同样增量整体走；关掉后各走各的。
        let beforeGroup = PetLayout.order.map { visibleFrameFor($0) }
        (pets[.shaolan] as? AudioPetController)?.simulateDragForTesting(dx: 30, dy: -12)
        var groupMoved = true
        for (index, id) in PetLayout.order.enumerated() {
            let after = visibleFrameFor(id)
            if abs(after.minX - beforeGroup[index].minX - 30) > 0.6
                || abs(after.minY - beforeGroup[index].minY + 12) > 0.6 {
                groupMoved = false
            }
        }
        check(groupMoved, "绑定相对位置：拖薄肌，四只一起平移")
        groupDragEnabled = false
        let beforeUnbound = PetLayout.order.map { visibleFrameFor($0) }
        (pets[.shaolan] as? AudioPetController)?.simulateDragForTesting(dx: 15, dy: 0)
        check(abs(visibleFrameFor(.sunpet).minX - beforeUnbound[1].minX) < 0.6,
              "关掉绑定后只有被拖的那只动")
        groupDragEnabled = true

        // 小数步长不累计漂移：4 步 × 2.5 应精确整体 +10。
        let beforeFraction = PetLayout.order.map { visibleFrameFor($0) }
        petDragBegan(.shaolan)
        for _ in 0..<4 { petDragged(.shaolan, dx: 2.5, dy: 2.5) }
        petDragEnded(.shaolan)
        var fractionOK = true
        for (index, id) in PetLayout.order.enumerated() where id != .shaolan {
            let after = visibleFrameFor(id)
            if abs(after.minX - beforeFraction[index].minX - 10) > 0.15
                || abs(after.minY - beforeFraction[index].minY - 10) > 0.15 {
                fractionOK = false
            }
        }
        check(fractionOK, "绑定拖动小数步长不累积漂移（4×2.5 = +10）")

        for pet in pets.values {
            pet.applySizeScale(1.0)
            pet.moveToDefaultPosition()
        }

        // 默认布局：三只语音窗口 + 果冻的可见图标，互不重叠且都在屏幕可见区里。
        for id in PetLayout.order {
            if let audio = pets[id] as? AudioPetController {
                audio.prepareDefaultLayoutForTesting()
            } else if let jelly = pets[id] as? JellyPetController {
                jelly.iconSide = 128
                jelly.moveToDefaultPosition()
            }
        }
        var layoutFrames: [PetID: NSRect] = [:]
        for id in PetLayout.order { layoutFrames[id] = visibleFrame(of: id) }
        check(layoutFrames.count == PetLayout.order.count, "四只默认布局都能算出来")
        if let screen = PetLayout.screen() {
            for id in PetLayout.order {
                if let frame = layoutFrames[id] {
                    check(screen.visibleFrame.contains(frame), "\(id.title) 默认位置完整落在屏幕可见区")
                }
            }
            var overlap = false
            for (index, first) in PetLayout.order.enumerated() {
                for second in PetLayout.order.dropFirst(index + 1) {
                    if let a = layoutFrames[first], let b = layoutFrames[second], a.intersects(b) {
                        overlap = true
                    }
                }
            }
            check(!overlap, "四只默认可见区域互不重叠")
        } else {
            check(false, "找不到屏幕")
        }

        let jelly = pets[.jelly]
        jelly?.setVisible(false)
        check(isPetVisible(.jelly) == false, "隐藏果冻生效")
        jelly?.setVisible(true)
        check(isPetVisible(.jelly) == true, "重新显示果冻生效")

        for id in PetLayout.order {
            check(!(pets[id]?.stateDescription.isEmpty ?? true), "\(id.title) 有状态诊断")
        }

        print("== \(checks) 项检查 ==")
        print(failures.isEmpty ? "PASS" : "FAIL: \(failures)")
        fflush(stdout)
        exit(failures.isEmpty ? 0 : 1)
    }

    /// 自定义内容包：安装 → 读取 → 替换薄肌 → 删除，全在临时目录里做，不碰用户真实内容。
    private func selfTestPetPack(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pethub-pack-selftest-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "local.pethub.selftest.pack"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? fm.removeItem(at: base)
            defaults.removePersistentDomain(forName: suiteName)
        }
        guard let resources = Bundle.main.resourceURL else {
            check(false, "自定义内容包：找不到 App 资源目录")
            return
        }
        let avatar = resources.appendingPathComponent("shaolan/face.png")
        let audio = resources.appendingPathComponent("shaolan/Clips/01.wav")
        guard fm.fileExists(atPath: avatar.path), fm.fileExists(atPath: audio.path) else {
            check(false, "自定义内容包：缺少测试素材")
            return
        }
        let store = PetPackStore(baseURL: base.appendingPathComponent("HeadPet", isDirectory: true))
        do {
            let pack = try store.install(name: "我的老师", avatarURL: avatar,
                                         clips: [(audio, "同学们好"), (audio, "下课")])
            check(pack.name == "我的老师" && pack.manifest.clips.count == 2,
                  "自定义内容包：安装 2 条语音并读出名字")
            guard let loaded = store.current(), let loadedClips = try? loaded.clips() else {
                check(false, "自定义内容包：重新读取失败")
                return
            }
            check(loadedClips.count == 2 && loadedClips.map(\.label) == ["同学们好", "下课"],
                  "自定义内容包：语音和中文一一对应")
            check(loaded.avatarImage() != nil, "自定义内容包：头像可读")

            defaults.removePersistentDomain(forName: suiteName)
            let controller = AudioPetController(profile: AudioPetProfiles.shaolan,
                                                settings: PetSettings(.shaolan, defaults: defaults),
                                                packStore: store)
            try controller.start()
            check(controller.isCustomHead && controller.displayTitle == "我的老师",
                  "自定义内容包：替换薄肌后名字变成「我的老师」")
            check(controller.clipCount == 2, "自定义内容包：替换薄肌后只有 2 句")
            controller.shutdown()

            let editor = CustomHeadImporterController(store: store, current: loaded,
                                                      onApply: {}, onRestore: {})
            check(editor.window != nil && (editor.window?.contentView?.subviews.count ?? 0) > 8,
                  "自定义内容包：编辑器窗口能建出来")
            editor.window?.contentView?.layoutSubtreeIfNeeded()
            let editorScroll = editor.window?.contentView?.subviews
                .compactMap { $0 as? NSScrollView }.first
            let editorTable = editorScroll?.documentView as? NSTableView
            check(editorTable?.numberOfRows == 2,
                  "自定义内容包：编辑器列出已有的 2 条语音")
            editor.close()

            // 导入一个已经做好的 petpack 文件夹（开源分发格式）。
            let source = base.appendingPathComponent("SourcePack", isDirectory: true)
            try fm.createDirectory(at: source.appendingPathComponent("clips", isDirectory: true),
                                   withIntermediateDirectories: true)
            try fm.copyItem(at: avatar, to: source.appendingPathComponent("avatar.png"))
            try fm.copyItem(at: audio, to: source.appendingPathComponent("clips/01.wav"))
            let sourceManifest = PetPackManifest(
                format: PetPackManifest.currentFormat,
                name: "导入的老师",
                author: "测试",
                avatar: "avatar.png",
                clips: [PetPackClip(file: "clips/01.wav", label: "导入的一句")])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(sourceManifest).write(to: source.appendingPathComponent("petpack.json"))
            let imported = try store.importPack(from: source)
            check(imported.name == "导入的老师"
                  && (try? imported.clips().map(\.label)) == ["导入的一句"],
                  "自定义内容包：能导入现成的 petpack 文件夹")

            try store.remove()
            check(!store.isInstalled, "自定义内容包：恢复原版后内容包被删掉")
        } catch {
            check(false, "自定义内容包自检失败：\(error.localizedDescription)")
        }
    }

    private func setOfVisibilityStates() -> Set<Bool> {
        Set(PetLayout.order.map { isPetVisible($0) })
    }

    // MARK: 四步链实测

    private func runChainTest() {
        relay.traceEnabled = true
        relayEnabled = true
        relay.isEnabled = true
        for pet in pets.values { pet.setRelayEnabled(true) }
        for id in PetLayout.order where id.isAudio {
            (pets[id] as? AudioPetController)?.silenceForDiagnostics()
        }
        chainAttempt = 0
        startChainAttempt()
    }

    private func startChainAttempt() {
        guard let shaolan = pets[.shaolan] as? AudioPetController else {
            print("FAIL 薄肌控制器不存在")
            exit(1)
        }
        chainAttempt += 1
        speechLog.removeAll()
        print("[chain] 第 \(chainAttempt) 次：3 秒后模拟点一下薄肌，等四步链跑完")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            shaolan.playNext()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 18.0) {
            self.finishChainAttempt()
        }
    }

    private func finishChainAttempt() {
        print("[chain] 实际开口 \(speechLog.count) 次：")
        for (index, speech) in speechLog.enumerated() {
            print("[chain]   \(index): \(speech.summary)")
        }
        let expected: [(PetID, Int, PetID)] = [
            (.shaolan, 0, .shaolan),
            (.sunpet, 1, .shaolan),
            (.fengge, 2, .shaolan),
            (.sunpet, 3, .shaolan),
        ]
        let ok = speechLog.count == expected.count && zip(speechLog, expected).allSatisfy { speech, want in
            speech.from == want.0 && speech.hop == want.1 && speech.root == want.2
        }
        if ok {
            print("PASS 四步捧哏链：薄肌 → 太对了 → 峰哥 → 太对了，第四跳后停")
            fflush(stdout)
            exit(0)
        }
        if chainAttempt < 2 {
            // 接话时自己还在播（系统忙、起播晚了）会按设计放弃这一捧；重试一次再下结论。
            print("[chain] 这次少了一句（接话时自己还在播，按设计会放弃这一捧），重试一次")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startChainAttempt()
            }
            return
        }
        print("FAIL 四步链不对（期望 4 次：薄肌/太对了/峰哥/太对了，hop 0/1/2/3，root 全是薄肌）")
        fflush(stdout)
        exit(1)
    }
}