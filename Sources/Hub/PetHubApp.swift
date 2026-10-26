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

    private let testing = CommandLine.arguments.contains("--self-test")
    private let chainTesting = CommandLine.arguments.contains("--chain-test")
    private let tracing = CommandLine.arguments.contains("--trace")
    private let dumping = CommandLine.arguments.contains("--dump-state")
    private let previewPath = PetHubApp.argumentValue(for: "--preview")

    private var speechLog: [PetSpeech] = []
    private var chainAttempt = 0

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !testing && !chainTesting && !dumping && previewPath == nil,
           anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }

        relayEnabled = hubDefaults.object(forKey: "hub.relayEnabled") as? Bool ?? true
        linkSizeEnabled = hubDefaults.object(forKey: "hub.linkSize") as? Bool ?? true
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

    func petSizeTierChanged(_ id: PetID, tier: Int) {
        guard linkSizeEnabled else { return }
        for other in PetLayout.order where other != id {
            pets[other]?.applySizeTier(tier)
        }
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
        let header = NSMenuItem(title: "桌宠合集 · 四只", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let visibility = NSMenuItem(title: "显示 / 隐藏", action: nil, keyEquivalent: "")
        let visibilityMenu = NSMenu()
        for (index, id) in PetLayout.order.enumerated() {
            let entry = menuItem(id.fullName, #selector(toggleVisibility(_:)), tag: index)
            entry.state = isPetVisible(id) ? .on : .off
            visibilityMenu.addItem(entry)
        }
        visibility.submenu = visibilityMenu
        menu.addItem(visibility)
        menu.addItem(.separator())

        for id in PetLayout.order {
            let submenu = NSMenuItem(title: id.title, action: nil, keyEquivalent: "")
            submenu.submenu = pets[id]?.makeMenu() ?? NSMenu()
            menu.addItem(submenu)
        }
        menu.addItem(.separator())

        let relayItem = menuItem("捧哏联动", #selector(toggleRelaySetting))
        relayItem.state = relayEnabled ? .on : .off
        menu.addItem(relayItem)

        let sizeLink = menuItem("大小联动（改一只，四只一起变）", #selector(toggleSizeLink))
        sizeLink.state = linkSizeEnabled ? .on : .off
        menu.addItem(sizeLink)

        let sizeRoot = NSMenuItem(title: "统一大小", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let commonTier = commonSizeTier()
        for (tier, name) in ["小", "中", "大"].enumerated() {
            let entry = menuItem(name, #selector(setAllSizeTiers(_:)), tag: tier)
            entry.state = commonTier == tier ? .on : .off
            sizeMenu.addItem(entry)
        }
        sizeRoot.submenu = sizeMenu
        menu.addItem(sizeRoot)

        menu.addItem(menuItem("全部显示", #selector(showAllPets)))
        menu.addItem(menuItem("全部隐藏", #selector(hideAllPets)))
        menu.addItem(menuItem("全部归位", #selector(resetAllPositions)))
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

    @objc private func setAllSizeTiers(_ sender: NSMenuItem) {
        for pet in pets.values { pet.applySizeTier(sender.tag) }
    }

    /// 四只档位一致时返回该档位，否则 nil（菜单里就不打勾）。
    private func commonSizeTier() -> Int? {
        let tiers = Set(PetLayout.order.compactMap { pets[$0]?.sizeTier })
        return tiers.count == 1 ? tiers.first : nil
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

    @objc private func showAbout() {
        let counts = PetLayout.order.compactMap { id -> String? in
            guard let audio = pets[id] as? AudioPetController else { return nil }
            return "\(id.title) \(audio.clipCount) 句"
        }.joined(separator: " · ")
        let alert = NSAlert()
        alert.messageText = "桌宠合集 1.1.0"
        alert.informativeText = """
        薄肌 · 太对了 · 峰哥 · 果冻，四只桌宠住在同一个 App 里。
        \(counts)

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
        print("version=1.1.0 relay=\(relayEnabled ? "on" : "off") pets=\(pets.count)")
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
        fflush(stdout)
        exit(0)
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
            let title = id.title as NSString
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

        check(pets.count == PetLayout.order.count, "四只桌宠都建好了（\(pets.count) 只）")
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

        // 大小联动：四只按各自的三档同步；关掉后各改各的。
        let savedLink = linkSizeEnabled
        linkSizeEnabled = true
        for pet in pets.values { pet.applySizeTier(2) }
        check(PetLayout.order.allSatisfy { pets[$0]?.sizeTier == 2 }, "统一大小：四只一起到「大」")
        pets[.shaolan]?.applySizeTier(0)
        petSizeTierChanged(.shaolan, tier: 0)
        check(PetLayout.order.allSatisfy { pets[$0]?.sizeTier == 0 }, "大小联动：改一只，其余三只跟着变")

        // 再走一遍真实菜单 action，确认 UI 接线也通（不是只有内部方法对）。
        if let sizeRoot = hubMenu.items.first(where: { $0.title == "统一大小" }),
           let big = sizeRoot.submenu?.items.first(where: { $0.title == "大" }),
           let action = big.action {
            NSApp.sendAction(action, to: big.target, from: big)
            check(PetLayout.order.allSatisfy { pets[$0]?.sizeTier == 2 },
                  "菜单「统一大小 → 大」四只一起变")
        } else {
            check(false, "菜单里找不到「统一大小」")
        }
        if let audioMenu = pets[.shaolan]?.makeMenu(),
           let sizeRoot = audioMenu.items.first(where: { $0.title == "人物大小" }),
           let small = sizeRoot.submenu?.items.first(where: { $0.title == "小" }),
           let action = small.action {
            NSApp.sendAction(action, to: small.target, from: small)
            check(PetLayout.order.allSatisfy { pets[$0]?.sizeTier == 0 },
                  "真实菜单：改薄肌大小，其余三只跟着变")
        } else {
            check(false, "薄肌菜单里找不到大小三档")
        }

        linkSizeEnabled = false
        pets[.shaolan]?.applySizeTier(2)
        petSizeTierChanged(.shaolan, tier: 2)
        check(pets[.shaolan]?.sizeTier == 2 && pets[.sunpet]?.sizeTier == 0,
              "关掉大小联动后各改各的")
        for pet in pets.values { pet.applySizeTier(1) }
        linkSizeEnabled = savedLink

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
        for id in PetLayout.order {
            if let audio = pets[id] as? AudioPetController {
                layoutFrames[id] = audio.windowFrame
            } else if let jelly = pets[id] as? JellyPetController {
                let side = jelly.iconSide
                layoutFrames[id] = NSRect(x: jelly.center.x - side / 2, y: jelly.center.y - side / 2,
                                          width: side, height: side)
            }
        }
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