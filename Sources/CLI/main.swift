import Foundation

/// `initials` — edits the same config the app watches; the running app picks up
/// changes within a moment. Exit codes: 0 ok, 1 not found, 2 usage or error.
let version = "1.1.1"

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

let usage = """
initials — pin apps to letters; hold either ⌘ + letter, or double-tap a ⌘ then a letter

  initials list [--side right|left] [--json]     show letters and their apps
  initials set <letter> <app> [--side right|left] pin an app (name, bundle id or /path/To.app)
  initials unset <letter> [--side right|left]     remove a letter
  initials import [--from keymaps.lua] [--side …] import Hammerspoon right_command letters
  initials enable|disable [right|left|all]         turn a side on or off
  initials hold on|off [--side right|left]         hold that ⌘ + letter (left: pinned letters only)
  initials tap on|off [--side right|left]          double-tap that ⌘ for the letter panel
  initials share on|off                            left ⌘ uses the right ⌘ letters
  initials status [--json]                         is the app running and intercepting?
  initials hammerspoon rcmd on|off                 switch MacKit's Hammerspoon rcmd
  initials path                                    print the config file path
"""

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) needs a value") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let json = flag("--json")
let sideOption = option("--side")
let side: Side = {
    guard let raw = sideOption else { return .right }
    guard let parsed = Side(rawValue: raw) else { fail("--side must be right or left") }
    return parsed
}()
let from = option("--from")

guard let command = args.first else { print(usage); exit(0) }
let rest = Array(args.dropFirst())

func loadConfig() -> Config {
    do { return try ConfigStore.load() } catch { fail("cannot read \(Paths.config.path): \(error.localizedDescription)") }
}
func save(_ config: Config) {
    do { try ConfigStore.save(config) } catch { fail("cannot write \(Paths.config.path): \(error.localizedDescription)") }
}
func printJSON(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

switch command {
case "--version", "version":
    print("initials \(version)")

case "help", "--help", "-h":
    print(usage)

case "path":
    print(Paths.config.path)

case "list":
    let config = loadConfig()
    let sides: [Side] = sideOption == nil ? [.right, .left] : [side]
    if json {
        var out: [String: Any] = [:]
        for s in sides {
            let c = config.side(s)
            out[s.rawValue] = [
                "enabled": c.enabled, "hold": c.hold, "doubleTap": c.doubleTap,
                "hideIfFrontmost": c.hideIfFrontmost, "cycleUnbound": c.cycleUnbound,
                "useRightBindings": s == .left ? c.useRightBindings : false,
                "bindings": config.bindings(for: s).mapValues { b -> [String: Any] in ["name": b.name, "bundleID": b.bundleID as Any? ?? NSNull(), "path": b.path as Any? ?? NSNull()] },
            ]
        }
        printJSON(out)
    } else {
        for s in sides {
            let c = config.side(s)
            let t = config.trigger(for: s)
            let ways = [t.hold ? "hold + letter" : nil, t.doubleTap ? "double-tap" : nil].compactMap { $0 }
            let shared = s == .left && c.useRightBindings ? " (same letters as right ⌘)" : ""
            print("\(s.rawValue) ⌘: \(ways.isEmpty ? "off" : ways.joined(separator: " + "))\(shared)")
            for conflict in s == .left ? config.leftHoldConflicts() : [] {
                print("  warning: holding left ⌘ takes over ⌘\(conflict.letter.uppercased()) (\(conflict.shortcut))")
            }
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

case "set":
    guard rest.count >= 2, let letter = Config.normalizedLetter(rest[0]) else { fail("usage: initials set <letter a–z> <app>") }
    let query = rest.dropFirst().joined(separator: " ")
    guard let binding = AppCatalog.resolve(query) else { fail("app not found: \(query)", code: 1) }
    var config = loadConfig()
    if side == .left && config.left.useRightBindings { fail("left ⌘ uses the right ⌘ letters; run `initials share off` first") }
    config.update(side) { $0.bindings[letter] = binding }
    save(config)
    print("\(side.rawValue) \(letter.uppercased()) → \(binding.name) (\(binding.path ?? binding.bundleID ?? ""))")

case "unset":
    guard let raw = rest.first, let letter = Config.normalizedLetter(raw) else { fail("usage: initials unset <letter>") }
    var config = loadConfig()
    guard config.side(side).bindings[letter] != nil else { fail("\(letter.uppercased()) is not pinned on \(side.rawValue)", code: 1) }
    config.update(side) { $0.bindings[letter] = nil }
    save(config)
    print("removed \(side.rawValue) \(letter.uppercased())")

case "import":
    let url = from.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? Hammerspoon.keymaps
    let imported: Hammerspoon.Imported
    do { imported = try Hammerspoon.importLetters(from: url) } catch { fail("cannot read \(url.path): \(error.localizedDescription)") }
    guard !imported.bindings.isEmpty || !imported.unresolved.isEmpty else { fail("no right_command letters in \(url.path)", code: 1) }
    var config = loadConfig()
    config.update(side) { s in s.bindings.merge(imported.bindings) { _, new in new } }
    save(config)
    for letter in imported.bindings.keys.sorted() { print("  \(letter.uppercased())  \(imported.bindings[letter]!.name)") }
    for miss in imported.unresolved { print("  \(miss.letter.uppercased())  \(miss.app)  [not installed, skipped]") }
    print("imported \(imported.bindings.count) letters into \(side.rawValue)")

case "enable", "disable":
    let on = command == "enable"
    let which = rest.first ?? "all"
    var config = loadConfig()
    switch which {
    case "right": config.right.enabled = on
    case "left": config.left.enabled = on
    case "all": config.right.enabled = on; config.left.enabled = on
    default: fail("usage: initials \(command) [right|left|all]")
    }
    save(config)
    print("\(which): \(on ? "on" : "off")")

case "hold", "tap":
    guard let value = rest.first, ["on", "off"].contains(value) else { fail("usage: initials \(command) on|off [--side right|left]") }
    var config = loadConfig()
    config.update(side) { s in
        if !s.enabled { s.hold = false; s.doubleTap = false; s.enabled = true }
        if command == "hold" { s.hold = value == "on" } else { s.doubleTap = value == "on" }
    }
    save(config)
    print("\(side.rawValue) ⌘ \(command == "hold" ? "hold + letter" : "double-tap"): \(value)")
    for conflict in config.leftHoldConflicts() where side == .left {
        print("warning: holding left ⌘ takes over ⌘\(conflict.letter.uppercased()) (\(conflict.shortcut))")
    }

case "share":
    guard let value = rest.first, ["on", "off"].contains(value) else { fail("usage: initials share on|off") }
    var config = loadConfig()
    config.left.useRightBindings = value == "on"
    save(config)
    print("left ⌘ uses right ⌘ letters: \(value)")

case "status":
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let status = (try? Data(contentsOf: Paths.status)).flatMap { try? decoder.decode(RuntimeStatus.self, from: $0) }
    let running = status.map { kill($0.pid, 0) == 0 } ?? false
    let rcmd = Hammerspoon.rcmdEnabled
    if json {
        printJSON(["running": running, "accessibilityTrusted": running && status!.accessibilityTrusted,
                   "intercepting": running && status!.tapEnabled, "version": status?.version ?? NSNull(),
                   "hammerspoonRcmd": rcmd, "config": Paths.config.path])
    } else {
        print("app: \(running ? "running (\(status!.version))" : "not running")")
        if running {
            print("accessibility: \(status!.accessibilityTrusted ? "granted" : "not granted")")
            print("intercepting: \(status!.tapEnabled ? "yes" : "no")")
        }
        print("hammerspoon rcmd: \(rcmd ? "on" : "off")")
        print("config: \(Paths.config.path)")
    }
    exit(running ? 0 : 3)

case "hammerspoon":
    guard rest.count == 2, rest[0] == "rcmd", ["on", "off"].contains(rest[1]) else { fail("usage: initials hammerspoon rcmd on|off") }
    do { print(try Hammerspoon.setRcmd(enabled: rest[1] == "on")) } catch { fail(error.localizedDescription) }

default:
    fail("unknown command: \(command)\n\n\(usage)")
}
