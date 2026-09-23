import AppKit

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tap = EventTap()
    private var config = Config()
    private var configError: String?
    private var statusItem: NSStatusItem?
    private var settings: SettingsWindowController?
    private let picker = PickerPanel()
    private var pickerTimer: Timer?
    private var trustTimer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(to: URL(fileURLWithPath: args[i + 1]), args: args)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        loadConfig()
        buildStatusItem()
        watchConfig()
        tap.onOutput = { [weak self] in self?.handle($0) }
        startTap()
        let firstRun = !FileManager.default.fileExists(atPath: Paths.config.path)
        if !args.contains("--background") && (firstRun || !EventTap.trusted || configError != nil) {
            showSettings(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop()
        try? FileManager.default.removeItem(at: Paths.status)
    }

    // MARK: Config

    private func loadConfig() {
        do {
            config = try ConfigStore.load()
            configError = nil
        } catch {
            // Keep running on defaults, but never overwrite the user's file.
            configError = T("配置文件无法读取：", "Could not read the config file: ") + error.localizedDescription
        }
        applyConfig()
    }

    private func applyConfig() {
        tap.engine.rightEnabled = config.right.enabled && !paused
        tap.engine.leftEnabled = config.left.enabled && !paused
        tap.engine.doubleTap = config.doubleTapSeconds
        settings?.replaceConfig(config)
        updateStatusIcon()
    }

    /// The CLI edits the same file; watch the folder because saves replace the file.
    private func watchConfig() {
        let dir = Paths.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        var pending = false
        source.setEventHandler { [weak self] in
            guard !pending else { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pending = false
                guard let self, let fresh = try? ConfigStore.load(), fresh != self.config else { return }
                self.config = fresh
                self.configError = nil
                self.applyConfig()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: Event tap

    private func startTap() {
        if tap.start() {
            trustTimer?.invalidate()
            trustTimer = nil
        } else if trustTimer == nil {
            // Not trusted yet: pick it up as soon as the user allows Accessibility.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard EventTap.trusted else { return }
                self?.startTap()
                self?.settings?.refreshStatus()
            }
        }
        writeStatus()
        updateStatusIcon()
    }

    private func handle(_ output: KeyOutput) {
        switch output {
        case let .act(side, letter):
            closePicker()
            Launcher.perform(letter: letter, side: side, config: config)
        case .openPicker:
            showPicker()
        case .closePicker:
            closePicker()
        case .pass, .swallow:
            break
        }
    }

    private func showPicker() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        picker.show(PickerPanel.entries(config: config, side: .left, running: Launcher.runningApps()), on: screen)
        pickerTimer?.invalidate()
        pickerTimer = Timer.scheduledTimer(withTimeInterval: config.pickerTimeoutSeconds, repeats: false) { [weak self] _ in
            self?.closePicker()
        }
    }

    private func closePicker() {
        pickerTimer?.invalidate()
        pickerTimer = nil
        tap.engine.pickerOpen = false
        picker.orderOut(nil)
    }

    private func writeStatus() {
        let status = RuntimeStatus(pid: ProcessInfo.processInfo.processIdentifier, accessibilityTrusted: EventTap.trusted,
                                   tapEnabled: tap.isEnabled, version: appVersion, updated: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(status).write(to: Paths.status, options: .atomic)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let active = tap.isEnabled && !paused && (config.right.enabled || config.left.enabled)
        let image = NSImage(systemSymbolName: active ? "command" : "command.circle", accessibilityDescription: "Initials")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = !active
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state: String
        if !EventTap.trusted { state = T("需要授权辅助功能", "Needs Accessibility access") }
        else if paused { state = T("已暂停", "Paused") }
        else { state = T("正在工作", "Active") }
        menu.addItem(NSMenuItem(title: "Initials — \(state)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let pause = NSMenuItem(title: paused ? T("恢复", "Resume") : T("暂停", "Pause"), action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        let prefs = NSMenuItem(title: T("设置…", "Settings…"), action: #selector(showSettings(_:)), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: T("退出 Initials", "Quit Initials"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePause() {
        paused.toggle()
        applyConfig()
    }

    @objc func showSettings(_ sender: Any?) {
        if settings == nil {
            let controller = SettingsWindowController(config: config)
            controller.onChange = { [weak self] fresh in
                self?.config = fresh
                self?.applyConfig()
            }
            controller.onRequestTrust = { EventTap.requestTrust() }
            controller.isTapRunning = { [weak self] in self?.tap.isEnabled ?? false }
            settings = controller
        }
        NSApp.mainMenu = MainMenu.build(target: self, settings: settings!)
        settings?.present()
    }
}

/// Standard menus so ⌘W, ⌘Q, ⌘1/⌘2 and editing keys work while Settings is open.
enum MainMenu {
    static func build(target: AppDelegate, settings: SettingsWindowController) -> NSMenu {
        let main = NSMenu()
        let app = NSMenu(title: "Initials")
        app.addItem(withTitle: T("关于 Initials", "About Initials"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: T("隐藏 Initials", "Hide Initials"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: T("退出 Initials", "Quit Initials"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: T("编辑", "Edit"))
        edit.addItem(withTitle: T("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: T("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: T("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let view = NSMenu(title: T("显示", "View"))
        let right = view.addItem(withTitle: T("右 ⌘ + 字母", "Right ⌘ + letter"), action: #selector(SideSwitch.right), keyEquivalent: "1")
        let left = view.addItem(withTitle: T("双击左 ⌘", "Double-tap left ⌘"), action: #selector(SideSwitch.left), keyEquivalent: "2")
        SideSwitch.shared.settings = settings
        right.target = SideSwitch.shared
        left.target = SideSwitch.shared
        let window = NSMenu(title: T("窗口", "Window"))
        window.addItem(withTitle: T("关闭", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: T("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        for menu in [app, edit, view, window] {
            let holder = NSMenuItem()
            holder.submenu = menu
            main.addItem(holder)
        }
        return main
    }
}

final class SideSwitch: NSObject {
    static let shared = SideSwitch()
    weak var settings: SettingsWindowController?
    @objc func right() { settings?.selectSide(.right) }
    @objc func left() { settings?.selectSide(.left) }
}
