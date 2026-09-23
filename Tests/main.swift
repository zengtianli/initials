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
