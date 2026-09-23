import Foundation

/// Which physical ⌘ key a table belongs to. Each can be held with a letter,
/// double-tapped for the letter picker, or both.
enum Side: String, Codable, CaseIterable {
    case right, left
}

/// An app pinned to a letter. The bundle identifier is authoritative; path and
/// name let the binding survive apps that move or have no identifier.
struct Binding: Codable, Equatable {
    var name: String
    var bundleID: String?
    var path: String?
}

struct SideConfig: Codable, Equatable {
    var enabled = true
    /// Hold this ⌘ and press a letter. On the left ⌘ only pinned letters are taken,
    /// so ⌘C, ⌘V and the rest keep working unless you pin those letters.
    var hold = true
    /// Tap this ⌘ twice quickly to show the letter picker.
    var doubleTap = false
    /// Pinned letters, keyed by lowercase a–z.
    var bindings: [String: Binding] = [:]
    /// Pressing the key of the app already in front hides it (press again to return).
    var hideIfFrontmost = true
    /// Letters without a binding cycle through running apps whose name starts with it.
    var cycleUnbound = true
    /// Left side only: use the right side's letters instead of its own table.
    var useRightBindings = false

    init() {}

    init(hold: Bool, doubleTap: Bool) {
        self.hold = hold
        self.doubleTap = doubleTap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Files from 1.0 have no trigger fields: right ⌘ held, left ⌘ double-tapped.
        let isLeft = decoder.codingPath.last?.stringValue == Side.left.rawValue
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        hold = try c.decodeIfPresent(Bool.self, forKey: .hold) ?? !isLeft
        doubleTap = try c.decodeIfPresent(Bool.self, forKey: .doubleTap) ?? isLeft
        bindings = try c.decodeIfPresent([String: Binding].self, forKey: .bindings) ?? [:]
        hideIfFrontmost = try c.decodeIfPresent(Bool.self, forKey: .hideIfFrontmost) ?? true
        cycleUnbound = try c.decodeIfPresent(Bool.self, forKey: .cycleUnbound) ?? true
        useRightBindings = try c.decodeIfPresent(Bool.self, forKey: .useRightBindings) ?? false
    }
}

struct Config: Codable, Equatable {
    var version = 1
    var right = SideConfig()
    var left: SideConfig = {
        var s = SideConfig(hold: false, doubleTap: true)
        s.useRightBindings = true
        return s
    }()
    /// Longest gap between the two taps of left ⌘, and the longest single tap.
    var doubleTapSeconds = 0.3
    /// The picker closes by itself after this long without a key.
    var pickerTimeoutSeconds = 4.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        right = try c.decodeIfPresent(SideConfig.self, forKey: .right) ?? defaults.right
        left = try c.decodeIfPresent(SideConfig.self, forKey: .left) ?? defaults.left
        doubleTapSeconds = try c.decodeIfPresent(Double.self, forKey: .doubleTapSeconds) ?? defaults.doubleTapSeconds
        pickerTimeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .pickerTimeoutSeconds) ?? defaults.pickerTimeoutSeconds
    }

    func side(_ side: Side) -> SideConfig { side == .right ? right : left }

    /// The letters a side actually uses (left may borrow the right table).
    func bindings(for side: Side) -> [String: Binding] {
        side == .left && left.useRightBindings ? right.bindings : self.side(side).bindings
    }

    mutating func update(_ side: Side, _ change: (inout SideConfig) -> Void) {
        if side == .right { change(&right) } else { change(&left) }
    }

    /// What the event tap needs for one ⌘ key. Holding left ⌘ only ever takes pinned
    /// letters: cycling every letter there would swallow ⌘C, ⌘V and friends.
    func trigger(for side: Side) -> Trigger {
        let s = self.side(side)
        return Trigger(hold: s.enabled && s.hold, doubleTap: s.enabled && s.doubleTap,
                       anyLetter: side == .right && s.cycleUnbound,
                       pinned: Trigger.mask(bindings(for: side).keys))
    }

    /// Pinned letters that holding left ⌘ would take away from common shortcuts.
    func leftHoldConflicts() -> [(letter: String, shortcut: String)] {
        guard left.enabled && left.hold else { return [] }
        let pinned = bindings(for: .left)
        return Self.commonShortcuts.filter { pinned[$0.letter] != nil }
    }

    static let commonShortcuts: [(letter: String, shortcut: String)] = [
        ("a", T("全选", "Select All")), ("c", T("拷贝", "Copy")), ("f", T("查找", "Find")), ("h", T("隐藏", "Hide")),
        ("m", T("最小化", "Minimize")), ("n", T("新建", "New")), ("o", T("打开", "Open")), ("p", T("打印", "Print")),
        ("q", T("退出", "Quit")), ("r", T("刷新", "Reload")), ("s", T("保存", "Save")), ("t", T("新标签页", "New Tab")),
        ("v", T("粘贴", "Paste")), ("w", T("关闭窗口", "Close")), ("x", T("剪切", "Cut")), ("z", T("撤销", "Undo")),
    ]

    static func normalizedLetter(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard s.count == 1, let c = s.unicodeScalars.first, ("a"..."z").contains(c) else { return nil }
        return s
    }
}

enum Paths {
    /// `$INITIALS_SUPPORT_DIR` isolates tests and side-by-side runs.
    static var supportDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cyou.tianli.initials", isDirectory: true)
    }
    static var config: URL { supportDirectory.appendingPathComponent("config.json") }
    static var status: URL { supportDirectory.appendingPathComponent("status.json") }
}

enum ConfigStore {
    /// Missing file → defaults. A corrupt file is reported, never silently replaced.
    static func load(from url: URL = Paths.config) throws -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: data)
    }

    /// Atomic replace, so the app's file watcher never reads half a file.
    static func save(_ config: Config, to url: URL = Paths.config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
        if url == Paths.config { MacKitKeys.publish(config) }
    }
}

/// When MacKit is installed, keep its shortcut catalog in step with these letters
/// (`mackit keys`, `mackit doctor`). Isolated runs never touch it.
enum MacKitKeys {
    static var file: URL { Hammerspoon.mackitConfigDirectory.appendingPathComponent("keys.d/initials.json") }

    static func publish(_ config: Config) {
        guard ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"] == nil,
              FileManager.default.fileExists(atPath: Hammerspoon.mackitConfigDirectory.path) else { return }
        var rows: [[String: String]] = []
        for side in Side.allCases {
            let trigger = config.trigger(for: side)
            let prefixes = (trigger.hold ? ["\(side.rawValue)-cmd+"] : []) + (trigger.doubleTap ? ["double-\(side.rawValue)-cmd "] : [])
            for prefix in prefixes {
                for (letter, binding) in config.bindings(for: side).sorted(by: { $0.key < $1.key }) {
                    rows.append(["component": "initials", "mode": "global", "key": prefix + letter,
                                 "description": "切换 " + binding.name, "source": Paths.config.path])
                }
            }
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// Written by the app so the CLI can report whether interception is live.
struct RuntimeStatus: Codable {
    var pid: Int32
    var accessibilityTrusted: Bool
    var tapEnabled: Bool
    var version: String
    var updated: Date
}

enum Lang {
    static let chinese = (Locale.preferredLanguages.first ?? "").hasPrefix("zh")
}

/// Chinese when the system prefers it, English otherwise.
func T(_ zh: String, _ en: String) -> String { Lang.chinese ? zh : en }
