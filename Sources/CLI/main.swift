import Foundation

/// `initials` — the Settings window and menu-bar state for scripts and agents. It reads and edits
/// the same config.json the app watches (the running app applies edits within a moment) through
/// Sources/Shared, the code the Settings window uses. Every command takes --help and --json.
/// Exit codes: 0 ok, 1 not found, 2 usage or error, 3 Initials not running, 4 app did not confirm.

struct Command {
    let usage: String
    let about: String
    var details = ""
    var positional: ClosedRange<Int> = 0...0
    var options: Set<String> = []
}

let valueOptions: Set<String> = ["--side", "--from"]
let flagOptions: Set<String> = ["--json", "--dry-run", "--help", "-h", "--version"]
let sideNote = "--side right|left picks the ⌘ key (default right)."
let dryNote = "--dry-run prints the result without saving."

let commandTable: [(String, Command)] = [
    ("list", Command(usage: "initials list [--side right|left] [--json]",
                     about: "Show each ⌘ key's triggers, options, shortcut warnings and pinned letters.",
                     details: "JSON per side: enabled, hold, doubleTap, effectiveHold, effectiveDoubleTap, hideIfFrontmost,\ncycleUnbound, useRightBindings, editable, conflicts [{letter, shortcut}], bindings {letter: {name,\nbundleID, path, found, resolvedPath}}; top level adds config, doubleTapSeconds, pickerTimeoutSeconds.",
                     options: ["--side"])),
    ("preview", Command(usage: "initials preview [<letter>…] [--side right|left] [--json]",
                        about: "What each letter would do right now (open, activate, hide or nothing), without doing it.",
                        details: "No letters: every letter the double-tap panel would show. Uses the running apps and the app in front.",
                        positional: 0...26, options: ["--side"])),
    ("status", Command(usage: "initials status [--json]",
                       about: "Is the app running, allowed Accessibility, intercepting, paused, active?",
                       details: "Exit 3 when Initials is not running (JSON is still printed, with ok false).")),
    ("login", Command(usage: "initials login [--json]",
                      about: "Does Initials open at login? (Read only; switch it in Settings.)")),
    ("path", Command(usage: "initials path [--json]", about: "Print the config file path.")),
    ("version", Command(usage: "initials version [--json]", about: "Print the version of the Initials.app this command ships in.")),
    ("set", Command(usage: "initials set <letter> <app> [--side right|left] [--dry-run] [--json]",
                    about: "Pin an app to a letter (app: name, bundle id or /path/To.app).",
                    details: "Left ⌘ has its own letters only after `initials share off`.",
                    positional: 2...64, options: ["--side", "--dry-run"])),
    ("unset", Command(usage: "initials unset <letter> [--side right|left] [--dry-run] [--json]",
                      about: "Remove a pinned letter.", positional: 1...1, options: ["--side", "--dry-run"])),
    ("move", Command(usage: "initials move <letter> <new-letter> [--side right|left] [--dry-run] [--json]",
                     about: "Move a pinned app to another letter (replaces what that letter held).",
                     positional: 2...2, options: ["--side", "--dry-run"])),
    ("import", Command(usage: "initials import [--from keymaps.lua] [--side right|left] [--dry-run] [--json]",
                       about: "Import Hammerspoon right_command letters (default ~/.hammerspoon/keymaps.lua).",
                       details: "Imported letters replace existing ones; apps that are not installed are skipped and listed.\nExit 1 when the file is missing or has no right_command letters.",
                       options: ["--side", "--from", "--dry-run"])),
    ("enable", Command(usage: "initials enable [right|left|all] [--dry-run] [--json]",
                       about: "Turn a ⌘ key back on (default all).", positional: 0...1, options: ["--dry-run"])),
    ("disable", Command(usage: "initials disable [right|left|all] [--dry-run] [--json]",
                        about: "Turn a ⌘ key off; saved, survives restarts (unlike pause).",
                        positional: 0...1, options: ["--dry-run"])),
    ("hold", Command(usage: "initials hold on|off [--side right|left] [--dry-run] [--json]",
                     about: "Hold that ⌘ + letter (left ⌘: pinned letters only).",
                     details: "Turning a trigger on also re-enables a disabled side, as the Settings checkbox does.",
                     positional: 1...1, options: ["--side", "--dry-run"])),
    ("tap", Command(usage: "initials tap on|off [--side right|left] [--dry-run] [--json]",
                    about: "Double-tap that ⌘ to show the letter panel.",
                    details: "Turning a trigger on also re-enables a disabled side, as the Settings checkbox does.",
                    positional: 1...1, options: ["--side", "--dry-run"])),
    ("cycle", Command(usage: "initials cycle on|off [--side right|left] [--dry-run] [--json]",
                      about: "Unpinned letters cycle through running apps whose name starts with the letter.",
                      positional: 1...1, options: ["--side", "--dry-run"])),
    ("hide-front", Command(usage: "initials hide-front on|off [--side right|left] [--dry-run] [--json]",
                           about: "Pressing the letter of the app already in front hides it.",
                           positional: 1...1, options: ["--side", "--dry-run"])),
    ("share", Command(usage: "initials share on|off [--dry-run] [--json]",
                      about: "Left ⌘ uses the right ⌘ letters (its own letters are kept for later).",
                      positional: 1...1, options: ["--dry-run"])),
    ("pause", Command(usage: "initials pause [--json]",
                      about: "Pause interception in the running app, like the menu-bar Pause (not saved).",
                      details: "Exit 3 when Initials is not running, 4 when it does not confirm within 2 seconds.")),
    ("resume", Command(usage: "initials resume [--json]", about: "Resume interception after a pause.",
                       details: "Exit 3 when Initials is not running, 4 when it does not confirm within 2 seconds.")),
    ("hammerspoon", Command(usage: "initials hammerspoon rcmd on|off [--json]",
                            about: "Switch an older MacKit's Hammerspoon rcmd module (exit 1 when it is not installed).",
                            positional: 2...2)),
]
let commands = Dictionary(uniqueKeysWithValues: commandTable)

let usage = """
initials — pin apps to letters; hold either ⌘ + letter, or double-tap a ⌘ then a letter

\(commandTable.map { "  " + $0.1.usage }.joined(separator: "\n"))

  initials <command> --help      details for one command (with --json: {"ok", "command", "help"})
Every command takes --json (an object with "ok"). Exit codes: 0 ok, 1 not found, 2 usage or error,
3 Initials not running, 4 the running app did not confirm. Edits go to config.json, which the running
app applies at once; INITIALS_SUPPORT_DIR=<dir> isolates everything for tests.
"""

// MARK: Parsing

var positional: [String] = []
var values: [String: String] = [:]
var flags: Set<String> = []
var unknown: [String] = []
do {
    let raw = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < raw.count {
        let arg = raw[i]
        if arg == "--" { positional += raw[(i + 1)...]; break }
        if valueOptions.contains(arg) {
            guard i + 1 < raw.count else { FileHandle.standardError.write(Data("\(arg) needs a value\n".utf8)); exit(2) }
            values[arg] = raw[i + 1]
            i += 2
            continue
        }
        if flagOptions.contains(arg) { flags.insert(arg) }
        else if arg.hasPrefix("-") && arg.count > 1 { unknown.append(arg) }
        else { positional.append(arg) }
        i += 1
    }
}
let json = flags.contains("--json")
let dryRun = flags.contains("--dry-run")
let wantsHelp = flags.contains("--help") || flags.contains("-h")
var name = positional.first ?? ""

// MARK: Output

func printJSON(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func fail(_ message: String, code: Int32 = 2, _ extra: [String: Any] = [:]) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    if json {
        var out: [String: Any] = ["ok": false, "error": message, "exitCode": Int(code)]
        if !name.isEmpty { out["command"] = name }
        printJSON(out.merging(extra) { current, _ in current })
    }
    exit(code)
}

func help(for command: Command) -> String {
    var text = "\(command.usage)\n\n\(command.about)"
    if !command.details.isEmpty { text += "\n\(command.details)" }
    var notes: [String] = []
    if command.options.contains("--side") { notes.append(sideNote) }
    if command.options.contains("--dry-run") { notes.append(dryNote) }
    notes.append("--json prints one object with \"ok\"; exit codes: 0 ok, 1 not found, 2 usage or error, 3 not running, 4 not confirmed.")
    return text + "\n\n" + notes.joined(separator: "\n")
}

let iso = ISO8601DateFormatter()

/// Help never acts. With --json it is still one object with "ok", like every other answer.
func showHelp(_ text: String, command: String? = nil) -> Never {
    if json { printJSON(["ok": true, "command": command.map { $0 as Any } ?? NSNull(), "help": text]) }
    else { print(text) }
    exit(0)
}

// MARK: Dispatch before any work

if name.isEmpty || name == "help" {
    if let bad = unknown.first, !wantsHelp { fail("unknown option \(bad)\n\n\(usage)") }
    if name == "help", positional.count > 1 {
        guard let command = commands[positional[1]] else { fail("unknown command: \(positional[1])\n\n\(usage)") }
        showHelp(help(for: command), command: positional[1])
    } else if flags.contains("--version") && !wantsHelp {
        name = "version"
    } else {
        showHelp(usage)
    }
}
guard let spec = commands[name] else { fail("unknown command: \(name)\n\n\(usage)") }
if wantsHelp { showHelp(help(for: spec), command: name) }
if let bad = unknown.first { fail("unknown option \(bad) for `\(name)`\n\n\(help(for: spec))") }
if flags.contains("--version") && name != "version" { fail("--version is not an option of `\(name)`") }
for option in ["--side", "--from", "--dry-run"] where (values[option] != nil || flags.contains(option)) && !spec.options.contains(option) {
    fail("`\(name)` does not take \(option)\n\n\(help(for: spec))")
}
let rest = Array(positional.dropFirst())
if name == "login", !rest.isEmpty {
    fail("`initials login` only reads the setting; switch “Open Initials at login” in Settings (macOS asks the app itself).")
}
guard spec.positional.contains(rest.count) else { fail("usage: \(spec.usage)") }

let sideOption = values["--side"]
let side: Side = {
    guard let raw = sideOption else { return .right }
    guard let parsed = Side(rawValue: raw) else { fail("--side must be right or left") }
    return parsed
}()

// MARK: Shared helpers

func loadConfig() -> Config {
    do { return try ConfigStore.load() } catch { fail("cannot read \(Paths.config.path): \(error.localizedDescription)") }
}

func bindingJSON(_ b: Binding) -> [String: Any] {
    let url = AppCatalog.url(for: b)
    return ["name": b.name, "bundleID": b.bundleID as Any? ?? NSNull(), "path": b.path as Any? ?? NSNull(),
            "found": url != nil, "resolvedPath": url?.path as Any? ?? NSNull()]
}

func sideJSON(_ config: Config, _ s: Side) -> [String: Any] {
    let c = config.side(s)
    let t = config.trigger(for: s)
    return [
        "enabled": c.enabled, "hold": c.hold, "doubleTap": c.doubleTap,
        "effectiveHold": t.hold, "effectiveDoubleTap": t.doubleTap,
        "hideIfFrontmost": c.hideIfFrontmost, "cycleUnbound": c.cycleUnbound,
        "useRightBindings": s == .left ? c.useRightBindings : false,
        "editable": config.bindingsEditable(s),
        "conflicts": (s == .left ? config.leftHoldConflicts() : []).map { ["letter": $0.letter, "shortcut": $0.id] },
        "bindings": config.bindings(for: s).mapValues(bindingJSON),
    ]
}

func sidesJSON(_ config: Config, _ sides: [Side] = Side.allCases) -> [String: Any] {
    Dictionary(uniqueKeysWithValues: sides.map { ($0.rawValue, sideJSON(config, $0) as Any) })
}

func letter(_ raw: String) -> String {
    guard let l = Config.normalizedLetter(raw) else { fail("not a letter a–z: \(raw)\n\nusage: \(spec.usage)") }
    return l
}

func onOff(_ raw: String) -> Bool {
    guard raw == "on" || raw == "off" else { fail("usage: \(spec.usage)") }
    return raw == "on"
}

let sharedLeftMessage = "left ⌘ uses the right ⌘ letters; run `initials share off` first"

/// Saves only a real change (and never in a dry run), then reports in the requested form.
/// Takes finished text lines rather than a closure, so it is compiled once, not per command.
func finish(_ before: Config, _ after: Config, _ extra: [String: Any] = [:], text: [String]) -> Never {
    let changed = before != after
    if changed && !dryRun {
        do { try ConfigStore.save(after) } catch { fail("cannot write \(Paths.config.path): \(error.localizedDescription)") }
    }
    if json {
        var out: [String: Any] = ["ok": true, "command": name, "changed": changed, "dryRun": dryRun,
                                  "config": Paths.config.path, "state": sidesJSON(after)]
        out.merge(extra) { _, new in new }
        printJSON(out)
    } else {
        text.forEach { print($0) }
        if dryRun { print(changed ? "(dry run: nothing saved)" : "(dry run: no change)") }
    }
    exit(0)
}

func conflictWarnings(_ config: Config) -> [String] {
    config.leftHoldConflicts().map { "  warning: holding left ⌘ takes over ⌘\($0.letter.uppercased()) (\($0.name))" }
}

/// The Initials.app this command ships in (…/Contents/Resources/bin/initials).
let hostContents: URL? = {
    guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
    let contents = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return contents.lastPathComponent == "Contents" ? contents : nil
}()
let hostInfo: [String: Any] = hostContents.flatMap {
    NSDictionary(contentsOf: $0.appendingPathComponent("Info.plist")) as? [String: Any]
} ?? [:]

// MARK: Commands

switch name {
case "version":
    let version = hostInfo["CFBundleShortVersionString"] as? String ?? "dev"
    let build = hostInfo["CFBundleVersion"] as? String
    if json {
        printJSON(["ok": true, "version": version, "build": build as Any? ?? NSNull(),
                   "app": hostContents?.deletingLastPathComponent().path as Any? ?? NSNull()])
    } else {
        print("initials \(version)")
    }

case "path":
    if json {
        printJSON(["ok": true, "config": Paths.config.path, "status": Paths.status.path,
                   "supportDirectory": Paths.supportDirectory.path])
    } else {
        print(Paths.config.path)
    }

case "list":
    let config = loadConfig()
    let sides: [Side] = sideOption == nil ? [.right, .left] : [side]
    if json {
        var out = sidesJSON(config, sides)
        out["ok"] = true
        out["config"] = Paths.config.path
        out["doubleTapSeconds"] = config.doubleTapSeconds
        out["pickerTimeoutSeconds"] = config.pickerTimeoutSeconds
        printJSON(out)
    } else {
        for s in sides {
            let c = config.side(s)
            let t = config.trigger(for: s)
            let ways = [t.hold ? "hold + letter" : nil, t.doubleTap ? "double-tap" : nil].compactMap { $0 }
            let shared = s == .left && c.useRightBindings ? " (same letters as right ⌘)" : ""
            print("\(s.rawValue) ⌘: \(ways.isEmpty ? "off" : ways.joined(separator: " + "))\(shared)")
            if s == .left { conflictWarnings(config).forEach { print($0) } }
            let bindings = config.bindings(for: s)
            if bindings.isEmpty { print("  (no pinned letters)") }
            for letter in bindings.keys.sorted() {
                let b = bindings[letter]!
                let found = AppCatalog.url(for: b) != nil ? "" : "  [not found]"
                print("  \(letter.uppercased())  \(b.name)\(found)")
            }
            print("  unpinned letters: \(c.cycleUnbound ? "cycle running apps" : "ignored")  · front app: \(c.hideIfFrontmost ? "hide" : "keep")")
        }
    }

case "preview":
    let config = loadConfig()
    let running = RunningApp.current()
    let front = RunningApp.frontmost
    let frontPID = front?.pid
    let trigger = config.trigger(for: side)
    let rows = rest.isEmpty ? LetterPreview.rows(config: config, side: side, running: running)
        : rest.map { LetterPreview.row(letter: letter($0), config: config, side: side, running: running) }
    let entries: [(row: LetterPreview, action: AppAction, hold: Bool)] = rows.map { row in
        let action = decide(letter: row.letter, bindings: config.bindings(for: side), options: config.side(side),
                            running: running, frontmostPID: frontPID)
        let bit = Trigger.mask([row.letter])
        return (row, action, trigger.hold && (trigger.anyLetter || trigger.pinned & bit != 0))
    }
    if json {
        printJSON([
            "ok": true, "side": side.rawValue, "frontmost": front?.name as Any? ?? NSNull(),
            "trigger": ["hold": trigger.hold, "doubleTap": trigger.doubleTap, "anyLetter": trigger.anyLetter],
            "letters": entries.map { e -> [String: Any] in [
                "letter": e.row.letter, "pinned": e.row.pinned, "title": e.row.title,
                "app": e.row.binding.map { bindingJSON($0) as Any } ?? NSNull(),
                "candidates": e.row.candidates.map(\.name),
                "action": e.action.verb, "target": e.action.appName as Any? ?? NSNull(),
                "hold": e.hold, "panel": trigger.doubleTap,
            ] },
        ])
    } else {
        let ways = [trigger.hold ? "hold + letter" : nil, trigger.doubleTap ? "double-tap panel" : nil].compactMap { $0 }
        print("\(side.rawValue) ⌘: \(ways.isEmpty ? "off" : ways.joined(separator: " + ")) · front app: \(front?.name ?? "none")")
        if entries.isEmpty { print("  (no letter does anything right now)") }
        for e in entries {
            let title = e.row.isEmpty ? "—" : e.row.title
            let reach = e.hold ? "" : (trigger.doubleTap ? "  (panel only)" : "  (not intercepted)")
            print("  \(e.row.letter.uppercased())  \(title.padding(toLength: 24, withPad: " ", startingAt: 0)) → \(e.action.summary)\(reach)")
        }
    }

case "status":
    let live = RuntimeStatus.live()
    let rcmd = Hammerspoon.rcmdEnabled
    var configError: String?
    let config: Config?
    do { config = try ConfigStore.load() } catch { config = nil; configError = error.localizedDescription }
    let paused = live?.paused
    let tapEnabled = live?.tapEnabled ?? false
    let intercepting = tapEnabled && !(paused ?? false)
    // The menu-bar icon's rule (Sources/Shared); unknown while the config cannot be read.
    let active = config?.isActive(tapEnabled: tapEnabled, paused: paused ?? false)
    let anySide = config.map { $0.right.enabled || $0.left.enabled }
    if json {
        var out: [String: Any] = [
            "ok": live != nil, "running": live != nil, "pid": live.map { Int($0.pid) } as Any? ?? NSNull(),
            "version": live?.version as Any? ?? NSNull(),
            "accessibilityTrusted": live?.accessibilityTrusted ?? false, "tapEnabled": tapEnabled,
            "paused": paused as Any? ?? NSNull(), "intercepting": intercepting,
            "active": active as Any? ?? NSNull(),
            "updated": live.map { iso.string(from: $0.updated) } as Any? ?? NSNull(),
            "hammerspoonRcmd": rcmd, "config": Paths.config.path, "configError": configError as Any? ?? NSNull(),
        ]
        if live == nil { out["error"] = "Initials is not running" }
        printJSON(out)
    } else {
        if let live {
            print("app: running (\(live.version), pid \(live.pid))")
            print("accessibility: \(live.accessibilityTrusted ? "granted" : "not granted")")
            print("intercepting: \(intercepting ? "yes" : paused == true ? "no (paused)" : "no")")
            if let active, let anySide { print("active: \(active ? "yes" : anySide ? "no" : "no (both ⌘ keys disabled)")") }
            print("status written: \(iso.string(from: live.updated))")
        } else {
            print("app: not running")
        }
        print("hammerspoon rcmd: \(rcmd ? "on" : Hammerspoon.rcmdInstalled ? "off" : "not installed")")
        print("config: \(Paths.config.path)")
        if let configError { print("config error: \(configError)") }
    }
    exit(live != nil ? 0 : 3)

case "pause", "resume":
    let want = name == "pause"
    guard let status = RuntimeStatus.live() else { fail("Initials is not running", code: 3) }
    if status.paused == want {
        if json { printJSON(["ok": true, "command": name, "paused": want, "changed": false, "pid": Int(status.pid)]) }
        else { print(want ? "already paused" : "already running") }
        exit(0)
    }
    DistributedNotificationCenter.default().postNotificationName(want ? RuntimeControl.pause : RuntimeControl.resume,
                                                                  object: RuntimeControl.scope, userInfo: nil,
                                                                  deliverImmediately: true)
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if let now = RuntimeStatus.read(), now.pid == status.pid, now.paused == want {
            if json { printJSON(["ok": true, "command": name, "paused": want, "changed": true, "pid": Int(now.pid)]) }
            else { print(want ? "paused (until resume or restart)" : "resumed") }
            exit(0)
        }
        usleep(50_000)
    }
    fail("Initials \(status.version) (pid \(status.pid)) did not confirm within 2 s"
         + (status.paused == nil ? "; this version predates pause support" : ""), code: 4)

case "login":
    guard let contents = hostContents, hostInfo["CFBundleIdentifier"] as? String == "cyou.tianli.initials" else {
        fail("login status needs the initials command inside Initials.app (Contents/Resources/bin)")
    }
    let process = Process()
    process.executableURL = contents.appendingPathComponent("MacOS/Initials")
    process.arguments = ["--login-item-status"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    do { try process.run() } catch { fail("cannot ask Initials: \(error.localizedDescription)") }
    if done.wait(timeout: .now() + 5) == .timedOut { process.terminate(); fail("Initials did not answer within 5 s") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0,
          let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let open = answer["openAtLogin"] as? Bool, let state = answer["status"] as? String else {
        fail("Initials gave no login-item status")
    }
    if json { printJSON(["ok": true, "openAtLogin": open, "status": state]) }
    else { print("open at login: \(open ? "on" : "off") (\(state))") }

case "set":
    let l = letter(rest[0])
    let query = rest.dropFirst().joined(separator: " ")
    guard let binding = AppCatalog.resolve(query) else { fail("app not found: \(query)", code: 1) }
    let before = loadConfig()
    var config = before
    guard config.bindingsEditable(side) else { fail(sharedLeftMessage) }
    let replaced = try! config.pin(binding, to: l, on: side)
    finish(before, config, ["side": side.rawValue, "letter": l, "binding": bindingJSON(binding),
                            "replaced": replaced.map { bindingJSON($0) as Any } ?? NSNull()],
           text: ["\(side.rawValue) \(l.uppercased()) → \(binding.name) (\(binding.path ?? binding.bundleID ?? ""))"])

case "unset":
    let l = letter(rest[0])
    let before = loadConfig()
    var config = before
    guard config.bindingsEditable(side) else { fail(sharedLeftMessage) }
    guard let removed = try! config.unpin(l, on: side) else { fail("\(l.uppercased()) is not pinned on \(side.rawValue)", code: 1) }
    finish(before, config, ["side": side.rawValue, "letter": l, "removed": bindingJSON(removed)],
           text: ["removed \(side.rawValue) \(l.uppercased())"])

case "move":
    let from = letter(rest[0]), to = letter(rest[1])
    let before = loadConfig()
    var config = before
    guard config.bindingsEditable(side) else { fail(sharedLeftMessage) }
    guard let binding = config.side(side).bindings[from] else { fail("\(from.uppercased()) is not pinned on \(side.rawValue)", code: 1) }
    let replaced = try! config.pin(binding, to: to, on: side, movingFrom: from)
    finish(before, config, ["side": side.rawValue, "from": from, "to": to, "binding": bindingJSON(binding),
                            "replaced": replaced.map { bindingJSON($0) as Any } ?? NSNull()],
           text: ["\(side.rawValue) \(from.uppercased()) → \(to.uppercased()): \(binding.name)"
                  + (replaced.map { " (replaced \($0.name))" } ?? "")])

case "import":
    let before = loadConfig()
    var config = before
    guard config.bindingsEditable(side) else { fail(sharedLeftMessage) }
    let url = values["--from"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? Hammerspoon.keymaps
    guard FileManager.default.fileExists(atPath: url.path) else { fail("import source not found: \(url.path)", code: 1) }
    let imported: Hammerspoon.Imported
    do { imported = try Hammerspoon.importLetters(from: url) } catch { fail("cannot read \(url.path): \(error.localizedDescription)") }
    guard !imported.bindings.isEmpty || !imported.unresolved.isEmpty else { fail("no right_command letters in \(url.path)", code: 1) }
    let replaced = try! config.merge(imported.bindings, into: side)
    finish(before, config, ["side": side.rawValue, "from": url.path, "imported": imported.bindings.mapValues(bindingJSON),
                            "unresolved": imported.unresolved.map { ["letter": $0.letter, "app": $0.app] },
                            "replaced": replaced],
           text: imported.bindings.keys.sorted().map { "  \($0.uppercased())  \(imported.bindings[$0]!.name)" }
               + imported.unresolved.map { "  \($0.letter.uppercased())  \($0.app)  [not installed, skipped]" }
               + ["\(dryRun ? "would import" : "imported") \(imported.bindings.count) letters into \(side.rawValue)"])

case "enable", "disable":
    let on = name == "enable"
    let which = rest.first ?? "all"
    let before = loadConfig()
    var config = before
    switch which {
    case "right": config.right.enabled = on
    case "left": config.left.enabled = on
    case "all": config.right.enabled = on; config.left.enabled = on
    default: fail("usage: \(spec.usage)")
    }
    finish(before, config, ["which": which, "enabled": on], text: ["\(which): \(on ? "on" : "off")"])

case "hold", "tap":
    let on = onOff(rest[0])
    let before = loadConfig()
    var config = before
    config.setTrigger(side) { s in if name == "hold" { s.hold = on } else { s.doubleTap = on } }
    finish(before, config, ["side": side.rawValue, name: on],
           text: ["\(side.rawValue) ⌘ \(name == "hold" ? "hold + letter" : "double-tap"): \(rest[0])"]
               + (side == .left ? conflictWarnings(config) : []))

case "cycle", "hide-front":
    let on = onOff(rest[0])
    let before = loadConfig()
    var config = before
    config.update(side) { s in if name == "cycle" { s.cycleUnbound = on } else { s.hideIfFrontmost = on } }
    finish(before, config, ["side": side.rawValue, name == "cycle" ? "cycleUnbound" : "hideIfFrontmost": on],
           text: [name == "cycle" ? "\(side.rawValue) ⌘ unpinned letters: \(on ? "cycle running apps" : "ignored")"
                                  : "\(side.rawValue) ⌘ app already in front: \(on ? "hide" : "keep")"])

case "share":
    let on = onOff(rest[0])
    let before = loadConfig()
    var config = before
    config.update(.left) { $0.useRightBindings = on }
    finish(before, config, ["useRightBindings": on],
           text: ["left ⌘ uses right ⌘ letters: \(rest[0])"] + conflictWarnings(config))

case "hammerspoon":
    guard rest[0] == "rcmd" else { fail("usage: \(spec.usage)") }
    let on = onOff(rest[1])
    guard Hammerspoon.rcmdInstalled else { fail(Hammerspoon.RcmdMissing().localizedDescription, code: 1) }
    let message: String
    do { message = try Hammerspoon.setRcmd(enabled: on) } catch { fail(error.localizedDescription) }
    if json { printJSON(["ok": true, "command": name, "rcmd": on, "message": message]) } else { print(message) }

default:
    fail("unknown command: \(name)\n\n\(usage)")
}
