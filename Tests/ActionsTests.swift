import Foundation

func testActions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("initials-actions-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("document.txt")
    try Data("fixture".utf8).write(to: file)
    let old = try JSONDecoder().decode(Binding.self, from: Data(#"{"name":"Finder","bundleID":"com.apple.finder"}"#.utf8))
    check(old.action == nil && old.displayName == "Finder", "old app bindings stay apps")
    var config = Config()
    for (i, kind) in ActionKind.allCases.enumerated() {
        let target: String? = kind == .openFolder ? folder.path : kind == .openFile ? file.path : kind == .openURL ? "https://example.com" : kind == .runShortcut ? "My Shortcut" : nil
        let action = try LetterAction(kind: kind, target: target)
        let binding = action.binding
        let l = String(UnicodeScalar(97 + i)!)
        try config.pin(binding, to: l, on: .right)
        check(decide(letter: l, bindings: [l: binding], options: SideConfig(), running: [RunningApp(pid: 1, name: binding.name)], frontmostPID: 1) == .execute(action), "action \(kind) never hides front app")
        check(LetterPreview.row(letter: l, config: config, side: .left, running: []).title == binding.displayName, "shared preview includes \(kind)")
        check(AppCatalog.url(for: binding) == nil, "actions are never resolved as apps")
    }
    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(Config.self, from: encoded)
    check(decoded == config, "all action types round trip")
    let export = folder.appendingPathComponent("config.json")
    try ConfigStore.save(config, to: export)
    let imported = try ConfigTransfer.read(from: export, resolve: { _ in fatalError("must not resolve actions as apps") })
    check(imported.config == config && imported.missing.isEmpty, "action import is portable and not a missing app")
    let merged = CloudSyncStore.merge(base: Config(), local: config, cloud: Config())
    check(merged.right.bindings == config.right.bindings, "actions survive cloud merge")
    func refuses(_ kind: ActionKind, _ target: String?) -> Bool {
        do { _ = try LetterAction(kind: kind, target: target); return false } catch { return true }
    }
    check(refuses(.openURL, "foo") && refuses(.openURL, "https://") && refuses(.openURL, "file:///tmp/foo"), "reject malformed URLs and file URL confusion")
    check(refuses(.showDownloads, "extra") && refuses(.openFile, nil) && refuses(.openFolder, "relative"), "reject wrong target shapes")
    let now = Date()
    let earlier = now.addingTimeInterval(-100)
    let newer = folder.appendingPathComponent("new.pdf"), older = folder.appendingPathComponent("old.pdf")
    let items = [ActionResolver.Item(url: newer, added: now, created: earlier), ActionResolver.Item(url: older, added: earlier, created: now)]
    check(ActionResolver.latest(items) == newer, "date added wins over creation date")
    check(ActionResolver.latest([.init(url: older, added: nil, created: now), .init(url: newer, added: nil, created: earlier)]) == older, "creation date is the fallback")
    for ext in ["download", "crdownload", "part", "partial", "tmp", "temp", "icloud"] {
        check(ActionResolver.latest(items + [.init(url: folder.appendingPathComponent("incomplete." + ext), added: now.addingTimeInterval(10), created: nil)]) == newer, "skip incomplete \(ext)")
    }
    check(ActionResolver.latest(items + [.init(url: folder.appendingPathComponent(".hidden"), added: now.addingTimeInterval(10), created: nil)]) == newer, "skip hidden items")
    let screenshot = folder.appendingPathComponent("Screenshot test.png")
    let screenItems = items + [.init(url: screenshot, added: earlier, created: earlier, screenshot: true)]
    check(ActionResolver.latest(screenItems, screenshotsOnly: true) == screenshot, "latest screenshot excludes newer non-screenshots")
    check(ActionResolver.latest([]) == nil, "empty directory has no item")
    let opened = try ActionResolver.resolve(LetterAction(kind: .openLastDownload), read: { _ in items })
    let revealed = try ActionResolver.resolve(LetterAction(kind: .revealLastDownload), read: { _ in items })
    check(opened == .open(newer), "latest download opens")
    check(revealed == .reveal(newer), "latest download reveals separately")
    var usedDirectory: URL?
    let resolved = try ActionResolver.resolve(LetterAction(kind: .openLastScreenshot), screenshots: folder, read: { directory in usedDirectory = directory; return screenItems })
    check(resolved == .open(screenshot) && usedDirectory == folder, "screenshot uses configured directory")
    let shown = try ActionResolver.resolve(LetterAction(kind: .showDownloads), downloads: folder)
    let fixed = try ActionResolver.resolve(LetterAction(kind: .openFile, target: file.path))
    let shortcut = try ActionResolver.resolve(LetterAction(kind: .runShortcut, target: "  My Shortcut  "))
    check(shown == .open(folder), "show downloads opens Finder directory")
    check(fixed == .open(file), "fixed file resolves")
    check(shortcut == .shortcut("My Shortcut"), "shortcut names are trimmed and passed as data")
    do { _ = try ActionResolver.resolve(LetterAction(kind: .openLastDownload), read: { _ in [] }); check(false, "empty downloads must fail") }
    catch { check(!error.localizedDescription.isEmpty, "empty downloads has useful error") }
    do { _ = try ActionResolver.resolve(LetterAction(kind: .openFolder, target: file.path)); check(false, "file cannot be folder") }
    catch { check(true, "wrong local target type rejected") }
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(100)], ofItemAtPath: file.path)
    let real = try ActionResolver.items(in: folder)
    check(real.contains { $0.url.resolvingSymlinksInPath() == file.resolvingSymlinksInPath() && $0.created != nil }, "real directory reader gets file metadata")
    var engine = KeyEngine()
    engine.right = config.trigger(for: .right)
    check(engine.handle(.keyDown(code: 5, flags: KeyEngine.command | KeyEngine.rightCommandDevice, isRepeat: false, time: 0)) == .act(.right, "g"), "bound action reaches right G")
    check(engine.handle(.keyDown(code: 5, flags: KeyEngine.command | KeyEngine.leftCommandDevice, isRepeat: false, time: 1)) == .pass, "left G still passes by default")
    let bad = Data(#"{"name":"bad","action":{"kind":"open-url"}}"#.utf8)
    check((try? JSONDecoder().decode(Binding.self, from: bad)) == nil, "bad action config is rejected rather than replaced")
}
