import AppKit
import UniformTypeIdentifiers

/// 「自定义桌宠」编辑窗口：换头像、加语音、给每条语音配中文。
///
/// 这是给不写代码的用户用的入口；做好的内容会安装到
/// `~/Library/Application Support/PetHub/HeadPet/`，替换薄肌并继续参与四步捧哏链。
final class CustomHeadImporterController: NSWindowController,
    NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let store: PetPackStore
    private let onApply: () -> Void
    private let onRestore: () -> Void
    private let currentPack: PetPack?

    private let nameField = NSTextField()
    private let avatarView = NSImageView()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: "恢复原版薄肌", target: nil, action: nil)
    private let removeAudioButton = NSButton(title: "删除选中", target: nil, action: nil)

    private var avatarURL: URL?
    private var clipURLs: [URL] = []
    private var clipLabels: [String] = []

    init(store: PetPackStore, current: PetPack?,
         onApply: @escaping () -> Void, onRestore: @escaping () -> Void) {
        self.store = store
        self.currentPack = current
        self.onApply = onApply
        self.onRestore = onRestore

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "自定义桌宠 · 替换薄肌"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
        loadCurrent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 布局

    private func buildUI() {
        guard let window, let content = window.contentView else { return }

        let title = NSTextField(labelWithString: "把薄肌换成你自己的角色")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "头像 + 语音 + 每条语音的中文。保存后会立刻出现在桌面上，太对了和峰哥照样接话。")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let nameLabel = NSTextField(labelWithString: "名字")
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.placeholderString = "例如：我的老师"
        nameField.font = .systemFont(ofSize: 14)

        avatarView.imageScaling = .scaleProportionallyUpOrDown
        avatarView.wantsLayer = true
        avatarView.layer?.borderWidth = 1
        avatarView.layer?.borderColor = NSColor.separatorColor.cgColor
        avatarView.layer?.cornerRadius = 12
        avatarView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let chooseAvatar = NSButton(title: "选择头像图片…", target: self,
                                    action: #selector(chooseAvatar))
        chooseAvatar.bezelStyle = .rounded

        let clipsTitle = NSTextField(labelWithString: "语音与中文")
        clipsTitle.font = .systemFont(ofSize: 13, weight: .medium)
        let addAudio = NSButton(title: "添加语音…", target: self, action: #selector(addAudio))
        addAudio.bezelStyle = .rounded
        removeAudioButton.target = self
        removeAudioButton.action = #selector(removeSelectedAudio)
        removeAudioButton.bezelStyle = .rounded
        removeAudioButton.isEnabled = false
        let hint = NSTextField(labelWithString: "支持 wav / m4a / mp3 / aiff；每条语音都要填一句中文。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let fileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileColumn.title = "语音"
        fileColumn.width = 220
        let captionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("caption"))
        captionColumn.title = "中文（字幕）"
        captionColumn.width = 380
        captionColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(fileColumn)
        tableView.addTableColumn(captionColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tableView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        let save = NSButton(title: "保存并应用", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        restoreButton.target = self
        restoreButton.action = #selector(restore)
        restoreButton.bezelStyle = .rounded

        for view in [title, subtitle, nameLabel, nameField, avatarView, chooseAvatar,
                     clipsTitle, addAudio, removeAudioButton, hint, scroll,
                     statusLabel, cancel, save, restoreButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        let margin: CGFloat = 22
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -margin),

            avatarView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            avatarView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            avatarView.widthAnchor.constraint(equalToConstant: 120),
            avatarView.heightAnchor.constraint(equalToConstant: 120),
            chooseAvatar.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            chooseAvatar.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 8),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 20),
            nameLabel.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: 4),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),

            clipsTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            clipsTitle.topAnchor.constraint(equalTo: chooseAvatar.bottomAnchor, constant: 22),
            addAudio.leadingAnchor.constraint(equalTo: clipsTitle.trailingAnchor, constant: 14),
            addAudio.centerYAnchor.constraint(equalTo: clipsTitle.centerYAnchor),
            removeAudioButton.leadingAnchor.constraint(equalTo: addAudio.trailingAnchor, constant: 8),
            removeAudioButton.centerYAnchor.constraint(equalTo: clipsTitle.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: removeAudioButton.trailingAnchor, constant: 14),
            hint.centerYAnchor.constraint(equalTo: clipsTitle.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -margin),

            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            scroll.topAnchor.constraint(equalTo: clipsTitle.bottomAnchor, constant: 8),
            scroll.heightAnchor.constraint(equalToConstant: 250),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            statusLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -margin),

            restoreButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            restoreButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
        ])
    }

    private func loadCurrent() {
        if let pack = currentPack {
            nameField.stringValue = pack.name
            avatarURL = pack.avatarURL
            avatarView.image = pack.avatarImage()
            clipURLs = pack.manifest.clips.map { pack.url(for: $0) }
            clipLabels = pack.manifest.clips.map(\.label)
            restoreButton.isEnabled = true
            statusLabel.stringValue = "正在使用自定义内容；重新保存会覆盖当前内容包。"
        } else {
            nameField.stringValue = "我的老师"
            restoreButton.isEnabled = false
            statusLabel.stringValue = "还没有自定义内容；保存后薄肌会换成你的角色。"
        }
        if avatarView.image == nil { updatePlaceholder() }
        tableView.reloadData()
    }

    private func updatePlaceholder() {
        let placeholder = NSImage(size: NSSize(width: 120, height: 120))
        placeholder.lockFocus()
        NSColor.quaternaryLabelColor.setStroke()
        let path = NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 104, height: 104),
                                xRadius: 10, yRadius: 10)
        path.lineWidth = 2
        path.stroke()
        let text = "头像" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (120 - size.width) / 2, y: (120 - size.height) / 2),
                  withAttributes: attrs)
        placeholder.unlockFocus()
        avatarView.image = placeholder
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int { clipURLs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        if identifier.rawValue == "file" {
            let label = NSTextField(labelWithString: clipURLs[row].lastPathComponent)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            return label
        }
        let field = NSTextField()
        field.stringValue = clipLabels[row]
        field.placeholderString = "这句语音对应的中文"
        field.font = .systemFont(ofSize: 13)
        field.tag = row
        field.delegate = self
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeAudioButton.isEnabled = tableView.selectedRow >= 0
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = field.tag
        guard clipLabels.indices.contains(row) else { return }
        clipLabels[row] = field.stringValue
    }

    // MARK: 交互

    @objc private func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.title = "选择桌宠头像"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        avatarURL = url
        avatarView.image = NSImage(contentsOf: url)
        statusLabel.stringValue = "头像：\(url.lastPathComponent)"
    }

    @objc private func addAudio() {
        let panel = NSOpenPanel()
        panel.title = "添加语音（可多选）"
        panel.allowedContentTypes = [.wav, .mpeg4Audio, .mp3, .aiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            clipURLs.append(url)
            clipLabels.append(url.deletingPathExtension().lastPathComponent)
        }
        tableView.reloadData()
        if !clipURLs.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: clipURLs.count - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(clipURLs.count - 1)
        }
        statusLabel.stringValue = "已添加 \(panel.urls.count) 条语音；记得给每条配中文。"
    }

    @objc private func removeSelectedAudio() {
        let row = tableView.selectedRow
        guard clipURLs.indices.contains(row) else { return }
        clipURLs.remove(at: row)
        clipLabels.remove(at: row)
        tableView.reloadData()
        removeAudioButton.isEnabled = tableView.selectedRow >= 0
    }

    @objc private func save() {
        window?.makeFirstResponder(nil)
        guard let avatarURL else {
            showAlert("还没有选头像", "先选一张图片作为头像。")
            return
        }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showAlert("还没有名字", "给桌宠起个名字，比如「我的老师」。")
            return
        }
        guard !clipURLs.isEmpty else {
            showAlert("还没有语音", "至少加一条语音，桌宠才有话说。")
            return
        }
        var clips: [(url: URL, label: String)] = []
        for (index, url) in clipURLs.enumerated() {
            let label = clipLabels[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                showAlert("有语音没配中文", "每条语音下面都要填一句中文，字幕会显示它。")
                return
            }
            clips.append((url, label))
        }
        do {
            try store.install(name: name, avatarURL: avatarURL, clips: clips,
                              author: NSFullUserName())
            statusLabel.stringValue = "已保存，正在切换…"
            onApply()
            close()
        } catch {
            showAlert("保存失败", error.localizedDescription)
        }
    }

    @objc private func restore() {
        let alert = NSAlert()
        alert.messageText = "恢复原版薄肌？"
        alert.informativeText = "会删掉当前自定义内容包，薄肌恢复成原来的 37 句。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.remove()
            onRestore()
            close()
        } catch {
            showAlert("恢复失败", error.localizedDescription)
        }
    }

    @objc private func cancel() {
        close()
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}