import Foundation

// Compiled with Sources/Shared by build.sh and run before signing.
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() { failures += 1; print("FAIL line \(line): \(message)") }
}

let R = KeyEngine.rightCommandDevice | KeyEngine.command
let L = KeyEngine.leftCommandDevice | KeyEngine.command
let codeC: UInt16 = 8, codeD: UInt16 = 2, codeM: UInt16 = 46, code1: UInt16 = 18

func tap(_ e: inout KeyEngine, at t: Double, hold: Double = 0.05) -> [KeyOutput] {
    [e.handle(.flagsChanged(flags: L, time: t)), e.handle(.flagsChanged(flags: 0, time: t + hold))]
}
func rtap(_ e: inout KeyEngine, at t: Double) -> [KeyOutput] {
    [e.handle(.flagsChanged(flags: R, time: t)), e.handle(.flagsChanged(flags: 0, time: t + 0.05))]
}

// MARK: Right ⌘ + letter

do {
    var e = KeyEngine()
    check(e.handle(.keyDown(code: codeD, flags: R, isRepeat: false, time: 0)) == .act(.right, "d"), "right ⌘ + D acts")
    check(e.handle(.keyUp(code: codeD, flags: R)) == .swallow, "its key-up is swallowed too")
    check(e.handle(.keyDown(code: codeD, flags: R, isRepeat: true, time: 0.5)) == .swallow, "auto-repeat is swallowed without acting")
    check(e.handle(.keyDown(code: codeC, flags: L, isRepeat: false, time: 1)) == .pass, "left ⌘C passes (copy keeps working)")
    check(e.handle(.keyUp(code: codeC, flags: L)) == .pass, "left ⌘C key-up passes")
    check(e.handle(.keyDown(code: codeC, flags: R | KeyEngine.shift, isRepeat: false, time: 1)) == .pass, "right ⇧⌘C passes")
    check(e.handle(.keyDown(code: codeC, flags: R | KeyEngine.option, isRepeat: false, time: 1)) == .pass, "right ⌥⌘C passes")
    check(e.handle(.keyDown(code: code1, flags: R, isRepeat: false, time: 1)) == .pass, "right ⌘1 passes (not a letter)")
    check(e.handle(.keyDown(code: codeM, flags: 0, isRepeat: false, time: 1)) == .pass, "plain typing passes")
    e.right.hold = false
    check(e.handle(.keyDown(code: codeD, flags: R, isRepeat: false, time: 2)) == .pass, "right hold off passes")
    e.right = Trigger(hold: true, anyLetter: false, pinned: Trigger.mask(["d"]))
    check(e.handle(.keyDown(code: codeD, flags: R, isRepeat: false, time: 3)) == .act(.right, "d"), "cycling off: pinned letter still acts")
    check(e.handle(.keyDown(code: codeM, flags: R, isRepeat: false, time: 3)) == .pass, "cycling off: unpinned letter passes")
}

// MARK: Left ⌘ held + letter

do {
    var e = KeyEngine()
    e.left = Trigger(hold: true, doubleTap: true, anyLetter: false, pinned: Trigger.mask(["d", "m"]))
    check(e.handle(.keyDown(code: codeD, flags: L, isRepeat: false, time: 0)) == .act(.left, "d"), "left ⌘ + pinned D acts")
    check(e.handle(.keyUp(code: codeD, flags: L)) == .swallow, "its key-up is swallowed")
    check(e.handle(.keyDown(code: codeC, flags: L, isRepeat: false, time: 1)) == .pass, "left ⌘C still copies (C not pinned)")
    check(e.handle(.keyDown(code: codeM, flags: L | KeyEngine.shift, isRepeat: false, time: 1)) == .pass, "left ⇧⌘M passes")
    check(e.handle(.keyDown(code: codeD, flags: R, isRepeat: false, time: 2)) == .act(.right, "d"), "right ⌘ still works alongside")
    check(e.handle(.keyDown(code: codeM, flags: L | R, isRepeat: false, time: 3)) == .act(.right, "m"), "both ⌘ held: right wins")
    e.left.anyLetter = true
    e.left.hold = false
    check(e.handle(.keyDown(code: codeD, flags: L, isRepeat: false, time: 4)) == .pass, "left hold off passes")
    e.left.hold = true
    _ = e.handle(.flagsChanged(flags: L, time: 5))
    _ = e.handle(.keyDown(code: codeD, flags: L, isRepeat: false, time: 5.05))
    _ = e.handle(.keyUp(code: codeD, flags: L))
    _ = e.handle(.flagsChanged(flags: 0, time: 5.1))
    check(tap(&e, at: 5.2) == [.pass, .pass], "hold + letter then a tap is not a double-tap")
}

// MARK: Right ⌘ double-tap, both sides together

do {
    var e = KeyEngine()
    e.right.doubleTap = true
    check(rtap(&e, at: 0) == [.pass, .pass], "first right tap does nothing")
    check(rtap(&e, at: 0.2) == [.pass, .openPicker(.right)], "second right tap opens the right picker (left double-tap also on)")
    check(e.handle(.keyDown(code: codeM, flags: 0, isRepeat: false, time: 0.5)) == .act(.right, "m"), "picker letter acts on right side")
    check(tap(&e, at: 1) == [.pass, .pass] && tap(&e, at: 1.2) == [.pass, .openPicker(.left)], "left double-tap still opens the left picker")
    _ = e.handle(.keyDown(code: KeyEngine.escape, flags: 0, isRepeat: false, time: 1.4))
    _ = rtap(&e, at: 2)
    check(tap(&e, at: 2.2) == [.pass, .pass], "right tap then left tap is not a double-tap")
    check(e.handle(.keyDown(code: codeD, flags: R, isRepeat: false, time: 3)) == .act(.right, "d"), "right hold and double-tap coexist")
    var f = KeyEngine()
    f.right = Trigger(hold: true, anyLetter: true)
    _ = rtap(&f, at: 0)
    check(rtap(&f, at: 0.2) == [.pass, .pass], "right double-tap off never opens")
}

// MARK: Left ⌘ double-tap


do {
    var e = KeyEngine()
    check(tap(&e, at: 0) == [.pass, .pass], "first tap does nothing")
    check(tap(&e, at: 0.2) == [.pass, .openPicker(.left)], "second quick tap opens the picker")
    check(e.pickerOpen, "engine knows the picker is open")
    check(e.handle(.keyDown(code: codeM, flags: 0, isRepeat: false, time: 0.5)) == .act(.left, "m"), "letter in picker acts on left side")
    check(!e.pickerOpen, "picker closes after a letter")
    check(e.handle(.keyUp(code: codeM, flags: 0)) == .swallow, "its key-up is swallowed")
}
do {
    var e = KeyEngine()
    _ = tap(&e, at: 0); _ = tap(&e, at: 0.2)
    check(e.handle(.keyDown(code: KeyEngine.escape, flags: 0, isRepeat: false, time: 0.5)) == .closePicker(swallow: true), "Esc closes and is swallowed")
    _ = tap(&e, at: 1); _ = tap(&e, at: 1.2)
    check(e.handle(.keyDown(code: code1, flags: 0, isRepeat: false, time: 1.5)) == .closePicker(swallow: false), "other key closes and passes")
}
do {
    var e = KeyEngine()
    _ = tap(&e, at: 0)
    check(tap(&e, at: 0.8) == [.pass, .pass], "slow second tap is just a new first tap")
    check(tap(&e, at: 1.0) == [.pass, .openPicker(.left)], "…which a quick third tap completes")
}
do {
    var e = KeyEngine()
    _ = e.handle(.flagsChanged(flags: L, time: 0))
    _ = e.handle(.keyDown(code: codeC, flags: L, isRepeat: false, time: 0.05))
    _ = e.handle(.keyUp(code: codeC, flags: L))
    _ = e.handle(.flagsChanged(flags: 0, time: 0.1))
    check(tap(&e, at: 0.2) == [.pass, .pass], "⌘C then a tap is not a double-tap")
    var f = KeyEngine()
    check(tap(&f, at: 0, hold: 0.6) == [.pass, .pass], "long hold is not a tap")
    check(tap(&f, at: 0.7) == [.pass, .pass], "…so the next tap starts over")
    var g = KeyEngine()
    _ = tap(&g, at: 0)
    _ = g.handle(.mouseDown)
    check(tap(&g, at: 0.2) == [.pass, .pass], "⌘-click between taps cancels")
    var h = KeyEngine()
    _ = tap(&h, at: 0)
    check(h.handle(.flagsChanged(flags: L | KeyEngine.shift, time: 0.15)) == .pass, "⇧ joins")
    check(h.handle(.flagsChanged(flags: 0, time: 0.2)) == .pass, "releasing a ⌘⇧ chord never opens the picker")
    check(!h.pickerOpen, "picker stays closed after a chord")
    check(tap(&h, at: 0.25) == [.pass, .pass], "⌘⇧ chord cancels the double-tap")
    var k = KeyEngine()
    k.left.doubleTap = false
    _ = tap(&k, at: 0)
    check(tap(&k, at: 0.2) == [.pass, .pass], "disabled left side never opens")
}

// MARK: Decisions (same rules as rcmd)

let music = RunningApp(pid: 10, name: "Music", bundleID: "com.apple.Music", path: "/System/Applications/Music.app")
let mail = RunningApp(pid: 11, name: "Mail", bundleID: "com.apple.mail", path: "/System/Applications/Mail.app")
let maps = RunningApp(pid: 12, name: "Maps", bundleID: "com.apple.Maps", path: "/System/Applications/Maps.app")
let pinMusic = Binding(name: "Music", bundleID: "com.apple.Music", path: "/System/Applications/Music.app")
var opts = SideConfig()
check(decide(letter: "m", bindings: ["m": pinMusic], options: opts, running: [], frontmostPID: nil) == .open(pinMusic), "pinned, not running → open")
check(decide(letter: "m", bindings: ["m": pinMusic], options: opts, running: [music], frontmostPID: 99) == .open(pinMusic), "pinned, in back → open")
check(decide(letter: "m", bindings: ["m": pinMusic], options: opts, running: [music], frontmostPID: 10) == .hide(music), "pinned, in front → hide")
opts.hideIfFrontmost = false
check(decide(letter: "m", bindings: ["m": pinMusic], options: opts, running: [music], frontmostPID: 10) == .open(pinMusic), "hide off → open")
opts.hideIfFrontmost = true
check(decide(letter: "m", bindings: [:], options: opts, running: [music, mail, maps], frontmostPID: 99) == .activate(mail), "unpinned → first by name")
check(decide(letter: "m", bindings: [:], options: opts, running: [music, mail, maps], frontmostPID: 11) == .activate(maps), "cycles to next")
check(decide(letter: "m", bindings: [:], options: opts, running: [music, mail, maps], frontmostPID: 10) == .activate(mail), "wraps around")
check(decide(letter: "m", bindings: [:], options: opts, running: [mail], frontmostPID: 11) == .hide(mail), "only one, in front → hide")
check(decide(letter: "q", bindings: [:], options: opts, running: [mail], frontmostPID: nil) == .nothing, "no match → nothing")
opts.cycleUnbound = false
check(decide(letter: "m", bindings: [:], options: opts, running: [mail], frontmostPID: nil) == .nothing, "cycling off → nothing")

// MARK: Config

do {
    let old = try! JSONDecoder().decode(Config.self, from: #"{"right":{"bindings":{"d":{"name":"DingTalk"}}}}"#.data(using: .utf8)!)
    check(old.right.enabled && old.right.cycleUnbound && old.left.useRightBindings, "missing fields take defaults")
    check(old.bindings(for: .left)["d"]?.name == "DingTalk", "left borrows right letters by default")
    check(old.right.hold && !old.right.doubleTap && !old.left.hold && old.left.doubleTap, "1.0 files keep right-hold / left-double-tap")
    check(Config() == (try! JSONDecoder().decode(Config.self, from: "{}".data(using: .utf8)!)), "empty file equals fresh defaults")
    let lt = old.trigger(for: .left), rt = old.trigger(for: .right)
    check(rt.hold && rt.anyLetter && !lt.hold && lt.doubleTap && !lt.anyLetter, "triggers follow the config")
    check(lt.pinned == Trigger.mask(["d"]), "left trigger knows the shared pinned letters")
    var both = old
    both.left.hold = true
    both.right.bindings["c"] = Binding(name: "Calendar")
    check(both.leftHoldConflicts().map(\.letter) == ["c"], "pinning C with left hold warns about ⌘C")
    both.left.enabled = false
    check(both.trigger(for: .left) == Trigger(pinned: Trigger.mask(["c", "d"])) && both.leftHoldConflicts().isEmpty, "disabled side triggers nothing")
    check(Config.normalizedLetter("D") == "d" && Config.normalizedLetter("dd") == nil && Config.normalizedLetter("1") == nil, "letter validation")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("initials-test-\(getpid())")
    let url = dir.appendingPathComponent("config.json")
    try! ConfigStore.save(old, to: url)
    check((try? ConfigStore.load(from: url)) == old, "save/load round trip")
    try! "{broken".write(to: url, atomically: true, encoding: .utf8)
    check((try? ConfigStore.load(from: url)) == nil, "corrupt file is an error, not silent defaults")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: Edits shared by Settings and the CLI

do {
    func refused(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return (error as? ConfigEditError) == .leftShared }
    }
    let music = Binding(name: "Music", bundleID: "com.apple.Music", path: nil)
    let mail = Binding(name: "Mail", bundleID: "com.apple.mail", path: nil)
    var c = Config()
    check(c.bindingsEditable(.right) && !c.bindingsEditable(.left), "shared left table is not editable")
    check(refused { try c.pin(music, to: "m", on: .left) } && refused { try c.unpin("m", on: .left) }
          && refused { try c.merge(["m": music], into: .left) } && c.left.bindings.isEmpty, "shared left refuses pin/unpin/import")
    check((try! c.pin(music, to: "m", on: .right)) == nil && c.right.bindings["m"] == music, "pin a free letter")
    check((try! c.pin(music, to: "m", on: .right)) == nil, "pinning the same app again replaces nothing")
    check((try! c.pin(mail, to: "m", on: .right)) == music, "pin reports the app it replaced")
    check((try! c.pin(mail, to: "n", on: .right, movingFrom: "m")) == nil && c.right.bindings == ["n": mail], "move clears the old letter")
    check((try! c.unpin("n", on: .right)) == mail && (try! c.unpin("n", on: .right)) == nil, "unpin returns what it removed")
    c.right.bindings = ["m": music, "d": mail]
    check((try! c.merge(["m": mail, "x": music, "d": mail], into: .right)) == ["m"], "import reports only letters whose app changed")
    c.left.useRightBindings = false
    check(c.bindingsEditable(.left) && (try! c.pin(music, to: "q", on: .left)) == nil && c.right.bindings["q"] == nil, "independent left edits its own table")
    c.right.enabled = false
    c.setTrigger(.right) { $0.doubleTap = true }
    check(c.right.enabled && !c.right.hold && c.right.doubleTap, "switching a trigger on re-enables the side with only that trigger")
    c.setTrigger(.right) { $0.hold = true }
    check(c.right.hold && c.right.doubleTap, "an enabled side keeps its other trigger")
    var shortcuts = Config()
    shortcuts.left.hold = true
    shortcuts.right.bindings = ["c": music, "v": mail, "k": music]
    check(shortcuts.leftHoldConflicts().map(\.id) == ["copy", "paste"], "conflicts carry stable ids")
}

// MARK: Letter preview (panel rows and `initials preview`)

do {
    let safari = RunningApp(pid: 20, name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
    let slack = RunningApp(pid: 21, name: "Slack", bundleID: "com.tinyspeck.slackmacgap", path: nil)
    let music = RunningApp(pid: 10, name: "Music", bundleID: "com.apple.Music", path: nil)
    var c = Config()
    c.right.bindings = ["m": Binding(name: "Music", bundleID: "com.apple.Music", path: nil)]
    let rows = LetterPreview.rows(config: c, side: .right, running: [slack, music, safari])
    check(rows.map(\.letter) == ["m", "s"], "rows list pinned letters and letters with running apps: \(rows.map(\.letter))")
    check(rows[0].pinned && rows[0].title == "Music" && rows[0].candidates.isEmpty, "pinned row shows the pinned app")
    check(!rows[1].pinned && rows[1].title == "Safari +1" && rows[1].candidates.map(\.name) == ["Safari", "Slack"], "cycle row: first by name +N")
    check(LetterPreview.row(letter: "q", config: c, side: .right, running: [safari]).isEmpty, "a letter with nothing is empty")
    check(LetterPreview.rows(config: c, side: .left, running: [safari]).map(\.letter) == ["m", "s"], "shared left previews the right letters")
    c.right.cycleUnbound = false
    check(LetterPreview.rows(config: c, side: .right, running: [safari]).map(\.letter) == ["m"], "cycling off: pinned letters only")
    check(cycleCandidates(letter: "s", running: [slack, safari]).map(\.pid) == [20, 21], "cycle order is by name")
    check(AppAction.open(Binding(name: "Music")).summary == "open Music" && AppAction.hide(safari).verb == "hide"
          && AppAction.nothing.summary == "nothing" && AppAction.nothing.appName == nil, "action summaries")
}

// MARK: Runtime status file

do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("initials-status-\(getpid())")
    let url = dir.appendingPathComponent("status.json")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! #"{"pid":42,"accessibilityTrusted":true,"tapEnabled":true,"version":"1.1.2","updated":"2026-09-29T03:11:22Z"}"#
        .write(to: url, atomically: true, encoding: .utf8)
    check(RuntimeStatus.read(from: url).map { $0.pid == 42 && $0.paused == nil } == true, "1.1.2 status files still read, paused unknown")
    let mine = RuntimeStatus(pid: 7, accessibilityTrusted: true, tapEnabled: true, paused: true, version: "t", updated: Date(timeIntervalSince1970: 1_800_000_000))
    mine.write(to: url)
    check(RuntimeStatus.read(from: url) == mine, "status round trip keeps paused")
    RuntimeStatus.remove(ifOwnedBy: 8, at: url)
    check(FileManager.default.fileExists(atPath: url.path), "another pid's quit leaves the status file")
    RuntimeStatus.remove(ifOwnedBy: 7, at: url)
    check(!FileManager.default.fileExists(atPath: url.path), "the owner's quit removes it")
    check(!RuntimeStatus.isInitialsProcess(getpid()) && !RuntimeStatus.isInitialsProcess(0)
          && !RuntimeStatus.isInitialsProcess(Int32.max), "only a live Initials binary counts as running")
    mine.write(to: url)
    check(RuntimeStatus.live(at: url) == nil, "a status file whose pid is not a live Initials app is no running copy")
    try? FileManager.default.removeItem(at: url)
    check(RuntimeStatus.live(at: url) == nil, "no status file, no running copy")
    var later = mine
    later.updated = mine.updated.addingTimeInterval(30)
    check(later.sameState(as: mine), "the watchdog does not rewrite a status that only aged")
    later.accessibilityTrusted = false
    check(!later.sameState(as: mine), "revoked Accessibility is a change the watchdog writes")
    var untapped = mine
    untapped.tapEnabled = false
    check(!untapped.sameState(as: mine) && !mine.sameState(as: nil), "a dead tap or a missing file is written again")
    mine.write(to: url)
    let written = try! Data(contentsOf: url)
    check(!later.sameState(as: mine) && !mine.publish(onlyIfChanged: true, to: url) && (try! Data(contentsOf: url)) == written,
          "a watchdog pass with nothing changed leaves the file alone")
    var aged = mine
    aged.updated = mine.updated.addingTimeInterval(60)
    check(!aged.publish(onlyIfChanged: true, to: url), "only a newer time is no reason to write")
    check(later.publish(onlyIfChanged: true, to: url) && RuntimeStatus.read(from: url)?.accessibilityTrusted == false,
          "a watchdog pass after Accessibility was revoked rewrites the file")
    try? FileManager.default.removeItem(at: url)
    check(mine.publish(onlyIfChanged: true, to: url) && RuntimeStatus.read(from: url) == mine, "a deleted status file is written again")
    try? FileManager.default.removeItem(at: url)
    var active = Config()
    check(active.isActive(tapEnabled: true, paused: false) && !active.isActive(tapEnabled: true, paused: true)
          && !active.isActive(tapEnabled: false, paused: false), "active needs the tap on and not paused")
    active.right.enabled = false
    check(active.isActive(tapEnabled: true, paused: false), "either ⌘ key enabled keeps the app active")
    active.left.enabled = false
    check(!active.isActive(tapEnabled: true, paused: false), "both ⌘ keys disabled is not active")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: Hammerspoon import

do {
    let lua = """
    M.right_command = {
    \td = "DingTalk",
    \tm = "Music",
    \t["F"] = "Finder",
    \ts = "moomoo", -- s=stock
    }
    M.ctrl_vim = { [4] = { {}, "left" } }
    """
    let letters = Hammerspoon.rightCommandLetters(in: lua)
    check(letters.map(\.letter) == ["d", "m", "f", "s"], "parses bare and bracketed keys, ignores comments: \(letters)")
    check(letters.first?.app == "DingTalk", "keeps app names")
    check(Hammerspoon.rightCommandLetters(in: "return {}").isEmpty, "no table → nothing")
    check(AppCatalog.resolve("Finder")?.bundleID == "com.apple.finder", "resolves Finder in CoreServices")
    check(AppCatalog.resolve("com.apple.Music")?.name == "Music", "resolves by bundle id")
    check(AppCatalog.resolve("/System/Applications/Music.app")?.bundleID == "com.apple.Music", "resolves by path")
    check(AppCatalog.resolve("NoSuchApp12345") == nil, "unknown app → nil")
}

// MARK: Cost per key event inside the tap callback (report only)

do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("initials-transfer-\(getpid())")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("export.json"), target = dir.appendingPathComponent("config.json")
    var original = Config()
    original.left.bindings = ["z": Binding(name: "Hidden left", bundleID: "test.hidden", path: "/old/Hidden.app")]
    original.right.bindings = ["m": pinMusic]
    original.right.doubleTap = true
    original.pickerTimeoutSeconds = 6
    try! ConfigTransfer.export(original, to: source)
    check((try! ConfigStore.load(from: source)) == original, "export keeps hidden left table and all options")
    let imported = try! ConfigTransfer.read(from: source, resolve: { $0.bundleID == "com.apple.Music" ? URL(fileURLWithPath: "/new/Music.app") : nil })
    check(imported.config.right.bindings["m"]?.path == "/new/Music.app", "import relocates app by resolver")
    check(imported.config.left.bindings == original.left.bindings && imported.missing.count == 1, "missing apps and hidden left letters survive")
    try! Data("corrupt prior config".utf8).write(to: target)
    let backup = try! ConfigTransfer.apply(imported, to: target)
    check((try! Data(contentsOf: backup!)) == Data("corrupt prior config".utf8), "import backs up corrupt prior bytes for recovery")
    check((try! ConfigStore.load(from: target)) == imported.config, "import restores readable full config")
    check((try! ConfigTransfer.apply(imported, to: target)) == nil, "repeated import is idempotent and leaves backup intact")
    for invalid in ["{}", #"{"version":2,"right":{},"left":{}}"#,
                    #"{"version":1,"right":{"bindings":{"1":{"name":"bad"}}},"left":{}}"#,
                    #"{"version":1,"right":{},"left":{},"doubleTapSeconds":0}"#] {
        try! Data(invalid.utf8).write(to: source)
        do { _ = try ConfigTransfer.read(from: source); check(false, "invalid import must fail: \(invalid)") }
        catch { check((try! ConfigStore.load(from: target)) == imported.config, "invalid import cannot mutate current configuration") }
    }
    let base = Config()
    var local = base, cloud = base
    local.right.bindings["m"] = pinMusic
    cloud.right.bindings["f"] = Binding(name: "Finder", bundleID: "com.apple.finder")
    cloud.left.doubleTap = false
    let merged = CloudSyncStore.merge(base: base, local: local, cloud: cloud)
    check(Set(merged.right.bindings.keys) == ["f", "m"] && !merged.left.doubleTap, "offline edits to separate letters and options merge")
    var removed = merged, changed = merged
    removed.right.bindings["m"] = nil
    changed.pickerTimeoutSeconds = 12
    check(CloudSyncStore.merge(base: merged, local: removed, cloud: changed).right.bindings["m"] == nil,
          "a local deletion survives a separate remote option change")
    local.right.bindings["m"] = Binding(name: "Local wins")
    cloud.right.bindings["m"] = Binding(name: "Remote edit")
    check(CloudSyncStore.merge(base: base, local: local, cloud: cloud).right.bindings["m"]?.name == "Local wins",
          "pending local edit wins a same-letter conflict")
}

do {
    var e = KeyEngine()
    let events: [KeyInput] = [
        .keyDown(code: codeM, flags: 0, isRepeat: false, time: 0), .keyUp(code: codeM, flags: 0),
        .keyDown(code: codeC, flags: L, isRepeat: false, time: 0), .keyUp(code: codeC, flags: L),
        .flagsChanged(flags: L, time: 0), .flagsChanged(flags: 0, time: 1),
        .keyDown(code: codeD, flags: R, isRepeat: false, time: 2), .keyUp(code: codeD, flags: R),
    ]
    let rounds = 250_000
    var acted = 0
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<rounds { for ev in events { if case .act = e.handle(ev) { acted += 1 } } }
    let ns = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(rounds * events.count)
    check(acted == rounds, "benchmark sanity")
    print(String(format: "bench: %.0f ns per key event (%d events)", ns, rounds * events.count))
}

print(failures == 0 ? "tests: all passed" : "tests: \(failures) failed")
exit(failures == 0 ? 0 : 1)
