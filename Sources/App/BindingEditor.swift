import AppKit
import UniformTypeIdentifiers

/// The same editor is used for adding and changing apps or actions.
final class BindingEditor: NSWindowController {
    var onSave: ((Binding, String) throws -> Void)?
    private let letterPicker = NSPopUpButton()
    private let typePicker = NSPopUpButton()
    private let target = NSTextField(string: "")
    private let browse = NSButton(title: T("选择…", "Choose…"), target: nil, action: nil)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let targetRow = NSStackView()
    private var app: Binding?
    private var kind: ActionKind? { typePicker.selectedItem?.representedObject as? ActionKind }

    init(bindings: [String: Binding], letter: String? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260), styleMask: [.titled], backing: .buffered, defer: true)
        window.title = T("字母绑定", "Letter Binding")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        for n in 97...122 {
            let l = String(UnicodeScalar(n)!)
            letterPicker.addItem(withTitle: l.uppercased() + (bindings[l].map { "  (\($0.displayName))" } ?? ""))
            letterPicker.lastItem?.representedObject = l
        }
        let selected = letter ?? (97...122).map { String(UnicodeScalar($0)!) }.first { bindings[$0] == nil } ?? "a"
        letterPicker.selectItem(at: Int(selected.unicodeScalars.first!.value - 97))
        typePicker.addItem(withTitle: T("应用", "Application"))
        for action in ActionKind.offered { typePicker.addItem(withTitle: action.title); typePicker.lastItem?.representedObject = action }
        typePicker.target = self; typePicker.action = #selector(typeChanged)
        target.placeholderString = T("目标", "Target")
        browse.target = self; browse.action = #selector(chooseTarget)
        browse.bezelStyle = .rounded
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed; errorLabel.font = .systemFont(ofSize: 12)
        let save = NSButton(title: T("保存", "Save"), target: self, action: #selector(saveBinding))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        let cancel = NSButton(title: T("取消", "Cancel"), target: self, action: #selector(cancelBinding))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let letterRow = NSStackView(views: [NSTextField(labelWithString: T("字母", "Letter")), letterPicker])
        let typeRow = NSStackView(views: [NSTextField(labelWithString: T("应用或动作", "App or action")), typePicker])
        targetRow.addArrangedSubview(target); targetRow.addArrangedSubview(browse)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, save])
        let stack = NSStackView(views: [letterRow, typeRow, hint, targetRow, errorLabel, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        for v in [letterRow, typeRow, hint, targetRow, errorLabel, buttons] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        target.setContentHuggingPriority(.init(1), for: .horizontal)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -18),
        ])
        if let letter, let binding = bindings[letter] {
            app = binding.action == nil ? binding : nil
            setType(binding.action?.kind, target: binding.action?.target ?? binding.path ?? binding.bundleID ?? binding.name)
        } else { setType(nil, target: "") }
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(on parent: NSWindow) { parent.beginSheet(window!) }
    private func dismiss() {
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        close()
    }
    @objc private func cancelBinding() { dismiss() }
    @objc private func typeChanged() { app = nil; target.stringValue = ""; refresh() }
    func setType(_ kind: ActionKind?, target value: String) {
        typePicker.selectItem(at: kind.flatMap { ActionKind.offered.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        target.stringValue = value
        refresh()
    }
    private func refresh() {
        hint.stringValue = kind?.hint ?? T("选择要打开或切换的应用。", "Choose an app to open or switch to.")
        targetRow.isHidden = kind != nil && !kind!.needsTarget
        browse.isHidden = kind != nil && ![.openFolder, .openFile].contains(kind!)
        errorLabel.stringValue = ""
        window?.contentView?.layoutSubtreeIfNeeded()
        if let size = window?.contentView?.fittingSize { window?.setContentSize(NSSize(width: 520, height: max(size.height, 230))) }
    }
    @objc private func chooseTarget() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = kind == .openFolder
        panel.canChooseFiles = kind != .openFolder
        panel.allowsMultipleSelection = false
        if kind == nil { panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            #if APP_STORE
            // The panel's access ends with this run; the saved grant lets the letter open it after a relaunch.
            if self.kind != nil {
                do { try FileGrants.remember(url) } catch { self.errorLabel.stringValue = error.localizedDescription }
            }
            #endif
            self.app = self.kind == nil ? AppCatalog.binding(for: url) : nil
            self.target.stringValue = self.kind == nil ? url.path : ActionResolver.portablePath(url)
        }
    }
    @objc private func saveBinding() { _ = save() }
    @discardableResult func save() -> Bool {
        do {
            let binding: Binding
            if let kind { binding = try LetterAction(kind: kind, target: kind.needsTarget ? target.stringValue : nil).binding }
            else {
                let existing = [app?.path, app?.bundleID, app?.name].contains { $0 == target.stringValue } ? app : nil
                guard let resolved = AppCatalog.resolve(target.stringValue) ?? existing else { throw ActionError(T("请选择已安装的应用。", "Choose an installed app.")) }
                binding = resolved
            }
            // Validate fixed local targets now; dynamic actions may be configured with an empty folder.
            if let action = binding.action, [.openFolder, .openFile].contains(action.kind) { _ = try ActionResolver.resolve(action) }
            guard let letter = letterPicker.selectedItem?.representedObject as? String else { return false }
            try onSave?(binding, letter)
            dismiss()
            return true
        } catch { errorLabel.stringValue = error.localizedDescription; return false }
    }

    func checkOffscreen(to directory: URL) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        var saved: Binding?
        onSave = { binding, _ in saved = binding }
        for action in ActionKind.offered {
            let value = action == .openFolder ? directory.path : action == .openFile ? directory.appendingPathComponent("editor-fixture.txt").path
                : action == .openURL ? "https://example.com" : action == .runShortcut ? "Fixture Shortcut" : ""
            setType(action, target: value)
            if action == .openFile { try Data("fixture".utf8).write(to: URL(fileURLWithPath: value)) }
            checks["binding_editor_" + action.rawValue] = save() && saved?.action?.kind == action
        }
        setType(.openURL, target: "bad URL")
        let before = saved
        checks["binding_editor_invalid_target"] = !save() && saved == before && !errorLabel.stringValue.isEmpty
        let snapshot = BindingEditor(bindings: [:], letter: "o")
        snapshot.setType(.openLastDownload, target: "")
        snapshot.window!.appearance = NSAppearance(named: .aqua)
        let content = snapshot.window!.contentView!
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layoutSubtreeIfNeeded()
        try writeRetinaPNG(of: content, to: directory.appendingPathComponent("binding-action.png"))
        let controls: [NSView] = [snapshot.letterPicker, snapshot.typePicker, snapshot.hint]
        checks["binding_editor_layout"] = controls.allSatisfy { view in
            let frame = content.convert(view.bounds, from: view)
            return frame.width > 0 && frame.height > 0 && content.bounds.insetBy(dx: -1, dy: -1).contains(frame)
        }
        checks["binding_editor_offscreen"] = !snapshot.window!.isVisible && !snapshot.window!.isKeyWindow && !snapshot.window!.isMainWindow
        snapshot.close()
        close()
        return checks
    }
}
