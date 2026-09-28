import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// One window for everything: permission, both sides' letter tables, options,
/// Hammerspoon import and login item. Keyboard: ⌘1/⌘2 switch side, ⌘N add,
/// ⌫ remove, ↩ change the selected app, ⌘W close.
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    var onChange: ((Config) -> Void)?
    var onRequestTrust: (() -> Void)?
    var isTapRunning: () -> Bool = { false }

    private(set) var config: Config
    private var side: Side = .right
    private var letters: [String] = []

    private let sidePicker = NSSegmentedControl(labels: [T("右 ⌘", "Right ⌘"), T("左 ⌘", "Left ⌘")],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let sideNote = NSTextField(wrappingLabelWithString: "")
    private let holdCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let tapCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let conflictLabel = NSTextField(wrappingLabelWithString: "")
    private let shareCheck = NSButton(checkboxWithTitle: T("使用与右 ⌘ 相同的字母", "Use the same letters as right ⌘"), target: nil, action: nil)
    private let hideCheck = NSButton(checkboxWithTitle: T("按下的 app 已在最前时，隐藏它（再按一次切回）", "If that app is already in front, hide it (press again to return)"), target: nil, action: nil)
    private let cycleCheck = NSButton(checkboxWithTitle: T("未指定的字母：在名字以它开头、正在运行的 app 之间轮换", "Unpinned letters cycle through running apps whose name starts with it"), target: nil, action: nil)
    private let table = BindingTableView()
    private let tableScroll = NSScrollView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let importButton = NSButton()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()
    private let hammerspoonLabel = NSTextField(wrappingLabelWithString: "")
    private let hammerspoonButton = NSButton()
    private let loginCheck = NSButton(checkboxWithTitle: T("登录时打开 Initials", "Open Initials at login"), target: nil, action: nil)
    private let message = NSTextField(labelWithString: "")

    init(config: Config) {
        self.config = config
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        window.title = T("Initials 设置", "Initials Settings")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.setActivationPolicy(.regular) // Dock and ⌘Tab while the window is open
        refreshStatus()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
    }

    func windowWillClose(_ notification: Notification) {
        if NSApp.activationPolicy() != .prohibited { NSApp.setActivationPolicy(.accessory) }
    }

    func replaceConfig(_ config: Config) {
        self.config = config
        reload()
    }

    // MARK: Layout

    private func build() {
        guard let content = window?.contentView else { return }
        sidePicker.target = self
        sidePicker.action = #selector(sideChanged)
        sidePicker.selectedSegment = 0
        sideNote.font = .systemFont(ofSize: 12)
        sideNote.textColor = .secondaryLabelColor
        conflictLabel.font = .systemFont(ofSize: 12)
        conflictLabel.textColor = .systemOrange
        for (check, action) in [(holdCheck, #selector(toggleHold)), (tapCheck, #selector(toggleTap)), (shareCheck, #selector(toggleShare)),
                                (hideCheck, #selector(toggleHide)), (cycleCheck, #selector(toggleCycle)),
                                (loginCheck, #selector(toggleLogin))] {
            check.target = self
            check.action = action
        }

        let letterColumn = NSTableColumn(identifier: .init("letter"))
        letterColumn.title = T("字母", "Letter")
        letterColumn.width = 60
        let appColumn = NSTableColumn(identifier: .init("app"))
        appColumn.title = "App"
        appColumn.width = 200
        let pathColumn = NSTableColumn(identifier: .init("path"))
        pathColumn.title = T("位置", "Location")
        pathColumn.width = 280
        [letterColumn, appColumn, pathColumn].forEach(table.addTableColumn)
        table.rowHeight = 26
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(changeApp)
        table.onDelete = { [weak self] in self?.removeBinding() }
        table.onReturn = { [weak self] in self?.changeApp() }
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.heightAnchor.constraint(equalToConstant: 210).isActive = true

        configure(addButton, T("添加…", "Add…"), #selector(addBinding))
        addButton.keyEquivalent = "n"
        addButton.keyEquivalentModifierMask = .command
        configure(removeButton, T("移除", "Remove"), #selector(removeBinding))
        configure(importButton, T("从 Hammerspoon 导入", "Import from Hammerspoon"), #selector(importHammerspoon))
        configure(permissionButton, T("打开辅助功能设置…", "Open Accessibility Settings…"), #selector(openAccessibility))
        configure(hammerspoonButton, "", #selector(toggleHammerspoon))
        permissionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hammerspoonLabel.font = .systemFont(ofSize: 12)
        hammerspoonLabel.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.lineBreakMode = .byTruncatingTail

        let permissionRow = NSStackView(views: [permissionLabel, spacer(), permissionButton])
        let hammerspoonRow = NSStackView(views: [hammerspoonLabel, hammerspoonButton])
        hammerspoonRow.alignment = .centerY
        let buttons = NSStackView(views: [addButton, removeButton, spacer(), importButton])
        let footer = NSStackView(views: [loginCheck, spacer(), message])

        let stack = NSStackView(views: [permissionRow, hammerspoonRow, separator(), sidePicker, sideNote, holdCheck, tapCheck, shareCheck,
                                        conflictLabel, tableScroll, buttons, hideCheck, cycleCheck, separator(), footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: sidePicker)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        for view in [permissionRow, hammerspoonRow, tableScroll, buttons, footer, sideNote, conflictLabel] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for view in stack.arrangedSubviews where view is NSBox {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 620),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func configure(_ button: NSButton, _ title: String, _ action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    /// Flexible horizontally only; a bare NSView would also soak up spare height.
    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    // MARK: State

    private func reload() {
        let s = config.side(side)
        sidePicker.selectedSegment = side == .right ? 0 : 1
        let key = side == .right ? T("右 ⌘", "right ⌘") : T("左 ⌘", "left ⌘")
        holdCheck.title = T("按住\(key)再按字母：直接切到 app", "Hold \(key) and press a letter: jump to the app")
        tapCheck.title = T("快速按两下\(key)：弹出字母面板，再按字母", "Tap \(key) twice: show the letter panel, then press a letter")
        sideNote.stringValue = side == .right
            ? T("两种方式可以同时打开，左右 ⌘ 也可以同时使用。右 ⌘ 同时按 ⇧⌥⌃ 时照常放行。",
                "Both ways can be on together, and on both ⌘ keys. Right ⌘ with ⇧⌥⌃ passes through.")
            : T("按住左 ⌘ 时只接管下表里指定了 app 的字母，其余 ⌘C、⌘V 等照常；面板 Esc 或 4 秒不按键自动关闭，不抢焦点。",
                "Holding left ⌘ only takes the letters pinned below; ⌘C, ⌘V and the rest keep working. The panel closes on Esc or after 4 seconds and never takes focus.")
        holdCheck.state = s.enabled && s.hold ? .on : .off
        tapCheck.state = s.enabled && s.doubleTap ? .on : .off
        let conflicts = side == .left ? config.leftHoldConflicts() : []
        conflictLabel.isHidden = conflicts.isEmpty
        conflictLabel.stringValue = T("⚠︎ 按住左 ⌘ 会占用这些常用快捷键：", "⚠︎ Holding left ⌘ takes over these shortcuts: ")
            + conflicts.map { "⌘\($0.letter.uppercased()) \($0.shortcut)" }.joined(separator: T("、", ", "))
            + T("。可关掉“使用与右 ⌘ 相同的字母”给左边单独设字母。", ". Turn off shared letters to give left ⌘ its own.")
        shareCheck.isHidden = side == .right
        shareCheck.state = s.useRightBindings ? .on : .off
        hideCheck.state = s.hideIfFrontmost ? .on : .off
        cycleCheck.state = s.cycleUnbound ? .on : .off
        let editable = !(side == .left && s.useRightBindings)
        addButton.isEnabled = editable
        removeButton.isEnabled = editable
        importButton.isEnabled = editable && FileManager.default.fileExists(atPath: Hammerspoon.keymaps.path)
        importButton.isHidden = !FileManager.default.fileExists(atPath: Hammerspoon.keymaps.path)
        table.isEnabled = editable
        letters = config.bindings(for: side).keys.sorted()
        table.reloadData()
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refreshStatus()
    }

    /// Rows come and go (warnings, Hammerspoon), so the window follows its content.
    private func fitWindow() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height
        guard abs(height - content.frame.height) > 0.5 else { return }
        var frame = window.frame
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: 620, height: height)))
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        window.setFrame(frame, display: true)
    }

    func refreshStatus() {
        let trusted = EventTap.trusted
        permissionLabel.stringValue = trusted
            ? (isTapRunning() ? T("✓ 已授权辅助功能，正在工作", "✓ Accessibility granted — active")
                              : T("✓ 已授权辅助功能", "✓ Accessibility granted"))
            : T("⚠︎ 需要授权“辅助功能”才能接收 ⌘ 按键", "⚠︎ Allow Accessibility so Initials can receive ⌘ keys")
        permissionLabel.textColor = trusted ? .systemGreen : .systemOrange
        permissionButton.isHidden = trusted
        let hasMacKit = FileManager.default.fileExists(atPath: Hammerspoon.mackitConfigDirectory.path)
        let rcmdOn = Hammerspoon.rcmdEnabled
        hammerspoonLabel.superview?.isHidden = !hasMacKit
        hammerspoonLabel.stringValue = rcmdOn
            ? T("Hammerspoon 的 rcmd 也在处理右 ⌘ + 字母。确认 Initials 可用后关掉它，避免两边同时处理。",
                "Hammerspoon's rcmd also handles right ⌘ + letter. Once Initials works, turn it off so only one tool handles the keys.")
            : T("Hammerspoon 的 rcmd 已关闭，由 Initials 处理。", "Hammerspoon's rcmd is off; Initials handles the keys.")
        hammerspoonButton.title = rcmdOn ? T("关闭 Hammerspoon rcmd", "Turn off Hammerspoon rcmd")
                                         : T("恢复 Hammerspoon rcmd", "Restore Hammerspoon rcmd")
        fitWindow()
    }

    private func commit(_ note: String? = nil) {
        do {
            try ConfigStore.save(config)
            message.stringValue = note ?? T("已保存", "Saved")
            onChange?(config)
        } catch {
            message.stringValue = error.localizedDescription
        }
        reload()
    }

    // MARK: Actions

    @objc private func sideChanged() {
        side = sidePicker.selectedSegment == 0 ? .right : .left
        reload()
    }

    func selectSide(_ newSide: Side) {
        side = newSide
        reload()
    }

    @objc private func toggleHold() { setTrigger { $0.hold = holdCheck.state == .on } }
    @objc private func toggleTap() { setTrigger { $0.doubleTap = tapCheck.state == .on } }

    /// The checkboxes show `enabled && trigger`, so switching one on also re-enables a side the CLI disabled.
    private func setTrigger(_ change: (inout SideConfig) -> Void) {
        config.update(side) { s in
            if !s.enabled { s.hold = false; s.doubleTap = false; s.enabled = true }
            change(&s)
        }
        commit()
    }
    @objc private func toggleShare() { config.update(.left) { $0.useRightBindings = shareCheck.state == .on }; commit() }
    @objc private func toggleHide() { config.update(side) { $0.hideIfFrontmost = hideCheck.state == .on }; commit() }
    @objc private func toggleCycle() { config.update(side) { $0.cycleUnbound = cycleCheck.state == .on }; commit() }

    @objc private func addBinding() { chooseApp(for: nil) }

    @objc private func changeApp() {
        guard table.selectedRow >= 0 else { return }
        chooseApp(for: letters[table.selectedRow])
    }

    @objc func removeBinding() {
        guard table.selectedRow >= 0, table.isEnabled else { return }
        let letter = letters[table.selectedRow]
        config.update(side) { $0.bindings[letter] = nil }
        commit(T("已移除 \(letter.uppercased())", "Removed \(letter.uppercased())"))
    }

    /// One dialog: pick the app, choose the letter in the panel's accessory view.
    private func chooseApp(for existing: String?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = T("指定", "Pin")
        panel.message = T("选择要指定给字母的 app", "Choose the app for this letter")
        let popup = NSPopUpButton()
        let taken = config.side(side).bindings
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let letter = String(UnicodeScalar(scalar)!)
            popup.addItem(withTitle: letter.uppercased() + (taken[letter].map { "  (\($0.name))" } ?? ""))
            popup.lastItem?.representedObject = letter
        }
        let preset = existing ?? (UnicodeScalar("a").value...UnicodeScalar("z").value)
            .map { String(UnicodeScalar($0)!) }.first { taken[$0] == nil } ?? "a"
        popup.selectItem(at: Int(UnicodeScalar(preset)!.value - UnicodeScalar("a").value))
        let label = NSTextField(labelWithString: T("字母：", "Letter:"))
        let accessory = NSStackView(views: [label, popup])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url, let binding = AppCatalog.binding(for: url),
                  let letter = popup.selectedItem?.representedObject as? String else { return }
            self.config.update(self.side) { s in
                if let existing, existing != letter { s.bindings[existing] = nil }
                s.bindings[letter] = binding
            }
            self.commit(T("\(letter.uppercased()) → \(binding.name)", "\(letter.uppercased()) → \(binding.name)"))
        }
    }

    @objc private func importHammerspoon() {
        do {
            let imported = try Hammerspoon.importLetters()
            config.update(side) { s in s.bindings.merge(imported.bindings) { _, new in new } }
            var note = T("已导入 \(imported.bindings.count) 个字母", "Imported \(imported.bindings.count) letters")
            if !imported.unresolved.isEmpty {
                note += T("；未找到：", "; not found: ") + imported.unresolved.map { "\($0.letter)=\($0.app)" }.joined(separator: ", ")
            }
            commit(note)
        } catch {
            message.stringValue = error.localizedDescription
        }
    }

    @objc private func toggleHammerspoon() {
        do {
            message.stringValue = try Hammerspoon.setRcmd(enabled: !Hammerspoon.rcmdEnabled)
        } catch {
            message.stringValue = error.localizedDescription
        }
        refreshStatus()
    }

    @objc private func openAccessibility() {
        onRequestTrust?()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            if loginCheck.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message.stringValue = error.localizedDescription
        }
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { letters.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let id = column?.identifier, let binding = config.bindings(for: side)[letters[row]] else { return nil }
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        var leading = cell.leadingAnchor
        switch id.rawValue {
        case "letter":
            text.stringValue = letters[row].uppercased()
            text.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        case "app":
            let icon = NSImageView()
            icon.image = AppCatalog.url(for: binding).map { NSWorkspace.shared.icon(forFile: $0.path) }
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
            ])
            leading = icon.trailingAnchor
            text.stringValue = binding.name
        default:
            let path = AppCatalog.url(for: binding)?.path ?? T("未找到", "Not found")
            text.stringValue = path
            text.textColor = AppCatalog.url(for: binding) == nil ? .systemRed : .secondaryLabelColor
        }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leading, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: Offscreen snapshot

    /// Uses the same reload/action methods as the visible settings window. The caller
    /// must isolate ConfigStore because removing a binding deliberately exercises save.
    func checkOffscreenInteractions(to directory: URL) throws -> [String: Bool] {
        precondition(ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"] != nil)
        var checks: [String: Bool] = [:]
        checks["settings_initial_table"] = table.numberOfRows == 2 && letters == ["c", "f"] && table.isEnabled
        selectSide(.left)
        checks["settings_shared_left"] = table.numberOfRows == 2 && !table.isEnabled && !shareCheck.isHidden
        var changed = config
        changed.left.hold = true
        replaceConfig(changed)
        checks["settings_conflict_refresh"] = !conflictLabel.isHidden && conflictLabel.stringValue.contains("⌘C")
        checks["settings_shared_controls_in_bounds"] = try snapshotSelfTestContent(to: directory.appendingPathComponent("settings-shared.png"))
        changed.left.useRightBindings = false
        changed.left.bindings = ["f": changed.right.bindings["f"]!]
        replaceConfig(changed)
        checks["settings_independent_left"] = table.numberOfRows == 1 && letters == ["f"] && table.isEnabled && conflictLabel.stringValue.contains("⌘F")
        var callbackCount = 0
        onChange = { _ in callbackCount += 1 }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        removeBinding()
        let persisted = try ConfigStore.load()
        checks["settings_remove_saved"] = table.numberOfRows == 0 && config.left.bindings.isEmpty
            && persisted.left.bindings.isEmpty && callbackCount == 1
        selectSide(.right)
        refreshStatus()
        checks["settings_refresh_preserves_right"] = table.numberOfRows == 2 && table.isEnabled && !permissionLabel.stringValue.isEmpty
        checks["settings_right_controls_in_bounds"] = try snapshotSelfTestContent(to: directory.appendingPathComponent("settings-right.png"))
        close()
        checks["settings_close_without_focus"] = window?.isVisible == false && window?.isKeyWindow == false
            && window?.isMainWindow == false && NSApp.activationPolicy() == .prohibited
        return checks
    }

    /// An unshown NSWindow's frame view may retain its previous title-bar geometry
    /// after a taller settings state. Render the actual content at its fitted size.
    private func snapshotSelfTestContent(to url: URL) throws -> Bool {
        window?.appearance = NSAppearance(named: .aqua)
        hammerspoonLabel.superview?.isHidden = true
        guard let content = window?.contentView else { return false }
        // Content alone has no NSThemeFrame to paint the light window background.
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layoutSubtreeIfNeeded()
        content.setFrameSize(content.fittingSize)
        content.layoutSubtreeIfNeeded()
        var controls: [NSView] = [permissionLabel, sidePicker, sideNote, holdCheck, tapCheck,
                                   tableScroll, addButton, removeButton, hideCheck, cycleCheck, loginCheck]
        if !shareCheck.isHidden { controls.append(shareCheck) }
        if !conflictLabel.isHidden { controls.append(conflictLabel) }
        let visible = controls.allSatisfy { control in
            let frame = content.convert(control.bounds, from: control)
            return frame.width > 0 && frame.height > 0 && content.bounds.insetBy(dx: -1, dy: -1).contains(frame)
        }
        try writeRetinaPNG(of: content, to: url)
        return visible
    }

    func snapshot(side: Side, to url: URL, appearance: NSAppearance?) throws {
        window?.appearance = appearance
        selectSide(side)
        // Docs show the product, not this Mac's Hammerspoon state.
        hammerspoonLabel.superview?.isHidden = true
        fitWindow()
        // The frame view includes the title bar and window buttons.
        guard let view = window?.contentView?.superview ?? window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        try writeRetinaPNG(of: view, to: url)
    }
}

/// ⌫ removes the selected letter; ↩ changes its app.
final class BindingTableView: NSTableView {
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if plain && (event.keyCode == 51 || event.keyCode == 117) { onDelete?() }
        else if plain && (event.keyCode == 36 || event.keyCode == 76) { onReturn?() }
        else { super.keyDown(with: event) }
    }
}
