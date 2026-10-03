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

    /// The menu-bar icon's "working" state and `initials status`'s `active`: the tap is on, not
    /// paused, and at least one ⌘ key is enabled.
    func isActive(tapEnabled: Bool, paused: Bool) -> Bool {
        tapEnabled && !paused && (right.enabled || left.enabled)
    }

    /// Pinned letters that holding left ⌘ would take away from common shortcuts.
    func leftHoldConflicts() -> [Shortcut] {
        guard left.enabled && left.hold else { return [] }
        let pinned = bindings(for: .left)
        return Self.commonShortcuts.filter { pinned[$0.letter] != nil }
    }

    /// `id` is the stable, locale-independent name (`initials list --json`); `name` is for people.
    struct Shortcut: Equatable {
        var letter: String, id: String, zh: String, en: String
        var name: String { T(zh, en) }
    }

    static let commonShortcuts: [Shortcut] = [
        ("a", "select-all", "全选", "Select All"), ("c", "copy", "拷贝", "Copy"), ("f", "find", "查找", "Find"),
        ("h", "hide", "隐藏", "Hide"), ("m", "minimize", "最小化", "Minimize"), ("n", "new", "新建", "New"),
        ("o", "open", "打开", "Open"), ("p", "print", "打印", "Print"), ("q", "quit", "退出", "Quit"),
        ("r", "reload", "刷新", "Reload"), ("s", "save", "保存", "Save"), ("t", "new-tab", "新标签页", "New Tab"),
        ("v", "paste", "粘贴", "Paste"), ("w", "close", "关闭窗口", "Close"), ("x", "cut", "剪切", "Cut"),
        ("z", "undo", "撤销", "Undo"),
    ].map { Shortcut(letter: $0.0, id: $0.1, zh: $0.2, en: $0.3) }

    // MARK: Edits shared by Settings and `initials`

    /// Left ⌘ that borrows the right ⌘ letters has no table of its own to edit; Settings greys it out.
    func bindingsEditable(_ side: Side) -> Bool { !(side == .left && left.useRightBindings) }

    /// The trigger checkboxes show `enabled && trigger`, so switching one also re-enables a disabled side.
    mutating func setTrigger(_ side: Side, _ change: (inout SideConfig) -> Void) {
        update(side) { s in
            if !s.enabled { s.hold = false; s.doubleTap = false; s.enabled = true }
            change(&s)
        }
    }

    /// Pins `binding` to `letter`; `movingFrom` clears the letter it came from (Settings' change-app sheet).
    /// Returns the different app that `letter` held before, if any.
    @discardableResult
    mutating func pin(_ binding: Binding, to letter: String, on side: Side, movingFrom existing: String? = nil) throws -> Binding? {
        guard bindingsEditable(side) else { throw ConfigEditError.leftShared }
        var replaced: Binding?
        update(side) { s in
            if let existing, existing != letter { s.bindings[existing] = nil }
            replaced = s.bindings[letter]
            s.bindings[letter] = binding
        }
        return replaced == binding ? nil : replaced
    }

    /// Removes a letter; returns what it held (nil when it was not pinned).
    @discardableResult
    mutating func unpin(_ letter: String, on side: Side) throws -> Binding? {
        guard bindingsEditable(side) else { throw ConfigEditError.leftShared }
        var removed: Binding?
        update(side) { s in removed = s.bindings.removeValue(forKey: letter) }
        return removed
    }

    /// Hammerspoon import: imported letters win. Returns the letters whose app changed.
    @discardableResult
    mutating func merge(_ imported: [String: Binding], into side: Side) throws -> [String] {
        guard bindingsEditable(side) else { throw ConfigEditError.leftShared }
        let before = self.side(side).bindings
        update(side) { s in s.bindings.merge(imported) { _, new in new } }
        return imported.keys.filter { before[$0] != nil && before[$0] != imported[$0] }.sorted()
    }

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
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        let data = try Data(contentsOf: url)
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

enum ConfigEditError: LocalizedError, Equatable {
    case leftShared
    var errorDescription: String? {
        T("左 ⌘ 正在使用右 ⌘ 的字母；先关掉“使用与右 ⌘ 相同的字母”。", "Left ⌘ uses the right ⌘ letters; turn off shared letters first.")
    }
}

/// Written by the app at launch, when Accessibility is granted and on every pause/resume; the tap's
/// existing 30 s watchdog rewrites it only when what it reports stopped being true (trust revoked,
/// tap disabled, file gone). No timer of its own, so the CLI can report whether interception is live.
struct RuntimeStatus: Codable, Equatable {
    var pid: Int32
    var accessibilityTrusted: Bool
    var tapEnabled: Bool
    /// Menu-bar Pause / `initials pause`: runtime only. Absent in files from 1.1.2 and earlier.
    var paused: Bool?
    var version: String
    var updated: Date

    static func read(from url: URL = Paths.status) -> RuntimeStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RuntimeStatus.self, from: data)
    }

    func write(to url: URL = Paths.status) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Writes the file unless `onlyIfChanged` and it already reports this state (the watchdog's pass).
    /// Returns whether it wrote.
    @discardableResult
    func publish(onlyIfChanged: Bool = false, to url: URL = Paths.status) -> Bool {
        if onlyIfChanged, sameState(as: Self.read(from: url)) { return false }
        write(to: url)
        return true
    }

    /// Quitting removes the file only when it is ours, so a stray second copy cannot erase the running app's state.
    static func remove(ifOwnedBy pid: Int32, at url: URL = Paths.status) {
        guard read(from: url)?.pid == pid else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Same reported state, whenever it was written: the watchdog rewrites the file only when this is false.
    func sameState(as other: RuntimeStatus?) -> Bool {
        guard var other else { return false }
        other.updated = updated
        return other == self
    }

    /// The pid is alive and is an Initials app binary (a reused pid from a crash is not).
    var isLive: Bool { Self.isInitialsProcess(pid) }

    /// The copy serving this support folder, if one is running. `initials status|pause|resume` talk to
    /// it, and a second app copy refuses to start while it exists. Scoped to the folder, so isolated
    /// self-tests (their own `INITIALS_SUPPORT_DIR`) and `--snapshot` renders (no status file) never
    /// stop the real app from starting.
    static func live(at url: URL = Paths.status) -> RuntimeStatus? {
        guard let status = read(from: url), status.isLive else { return nil }
        return status
    }

    static func isInitialsProcess(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer).hasSuffix(".app/Contents/MacOS/Initials")
    }
}

/// `initials pause|resume` → the running app. Posts carry the support folder as their object,
/// so an isolated run (`INITIALS_SUPPORT_DIR`) never reaches the installed app.
enum RuntimeControl {
    static let pause = Notification.Name("cyou.tianli.initials.pause")
    static let resume = Notification.Name("cyou.tianli.initials.resume")
    /// The folder's real path. The app creates the folder before listening and the CLI only posts
    /// after reading status.json from it, so both ends resolve an existing folder the same way
    /// (`standardizedFileURL` would drop /private only once the folder exists).
    static var scope: String {
        let path = Paths.supportDirectory.path
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

enum Lang {
    static let chinese = (Locale.preferredLanguages.first ?? "").hasPrefix("zh")
}

/// Chinese when the system prefers it, English otherwise.
func T(_ zh: String, _ en: String) -> String { Lang.chinese ? zh : en }
