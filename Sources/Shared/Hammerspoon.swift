import Foundation

/// Bridge for people coming from a Hammerspoon "rcmd" setup: read its right-⌘
/// letters, and (with an older MacKit that still has the module) switch its own
/// interception off so only one tool handles the keys.
enum Hammerspoon {
    static var keymaps: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.hammerspoon/keymaps.lua").resolvingSymlinksInPath()
    }

    /// Parses a Lua table such as `M.right_command = { d = "DingTalk", m = "Music" }`.
    static func rightCommandLetters(in source: String) -> [(letter: String, app: String)] {
        guard let start = source.range(of: #"right_command\s*=\s*\{"#, options: .regularExpression),
              let end = source[start.upperBound...].firstIndex(of: "}") else { return [] }
        let body = String(source[start.upperBound..<end])
        let entry = try! NSRegularExpression(pattern: #"(?:\[\s*"([A-Za-z])"\s*\]|\b([A-Za-z]))\s*=\s*"([^"]+)""#)
        return entry.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { m in
            let letter = [1, 2].compactMap { Range(m.range(at: $0), in: body).map { String(body[$0]) } }.first
            guard let letter, let app = Range(m.range(at: 3), in: body).map({ String(body[$0]) }) else { return nil }
            return (letter.lowercased(), app)
        }
    }

    struct Imported {
        var bindings: [String: Binding]
        var unresolved: [(letter: String, app: String)]
    }

    static func importLetters(from url: URL = keymaps) throws -> Imported {
        let source = try String(contentsOf: url, encoding: .utf8)
        let installed = AppCatalog.installed()
        var result = Imported(bindings: [:], unresolved: [])
        for (letter, app) in rightCommandLetters(in: source) {
            if let binding = AppCatalog.resolve(app, installed: installed) {
                result.bindings[letter] = binding
            } else {
                result.unresolved.append((letter, app))
            }
        }
        return result
    }

    // MARK: MacKit's rcmd module

    static var mackitConfigDirectory: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/.config")
        return base.appendingPathComponent("mackit", isDirectory: true)
    }
    static var overrides: URL { mackitConfigDirectory.appendingPathComponent("hotkey_overrides.json") }

    /// MacKit retired its rcmd module on 2026-09-27; only an older MacKit still has one to switch.
    static var rcmdModule: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.hammerspoon/modules/rcmd.lua")
    }
    static var rcmdInstalled: Bool { FileManager.default.fileExists(atPath: rcmdModule.path) }

    /// MacKit enables rcmd for the "tianli" profile unless `features.rcmd` is false.
    static var rcmdEnabled: Bool {
        guard rcmdInstalled else { return false }
        let profileURL = mackitConfigDirectory.appendingPathComponent("profile.json")
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              profile["profile"] as? String == "tianli" else { return false }
        let features = (readOverrides()["features"] as? [String: Any]) ?? [:]
        return features["rcmd"] as? Bool ?? true
    }

    static func readOverrides() -> [String: Any] {
        guard let data = try? Data(contentsOf: overrides),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    /// Sets `features.rcmd`, keeping every other override, then asks Hammerspoon to reload.
    @discardableResult
    static func setRcmd(enabled: Bool) throws -> String {
        // Writing the flag and reloading Hammerspoon without the module would only disturb it.
        guard rcmdInstalled else { throw RcmdMissing() }
        var json = readOverrides()
        var features = (json["features"] as? [String: Any]) ?? [:]
        features["rcmd"] = enabled
        json["features"] = features
        try FileManager.default.createDirectory(at: mackitConfigDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: overrides, options: .atomic)
        return reload()
    }

    struct RcmdMissing: LocalizedError {
        var errorDescription: String? {
            T("没有找到 MacKit 的 Hammerspoon rcmd 模块（~/.hammerspoon/modules/rcmd.lua），无需切换。",
              "MacKit's Hammerspoon rcmd module (~/.hammerspoon/modules/rcmd.lua) is not installed; nothing to switch.")
        }
    }

    private static func reload() -> String {
        guard let hs = ["/opt/homebrew/bin/hs", "/usr/local/bin/hs"].first(where: FileManager.default.isExecutableFile) else {
            return T("已写入设置；请在 Hammerspoon 菜单里选 Reload Config。", "Saved. Choose Reload Config in Hammerspoon.")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: hs)
        p.arguments = ["-c", "hs.timer.doAfter(0.2, hs.reload)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch {
            return T("已写入设置；请在 Hammerspoon 菜单里选 Reload Config。", "Saved. Choose Reload Config in Hammerspoon.")
        }
        return p.terminationStatus == 0
            ? T("已写入设置，Hammerspoon 已重新加载。", "Saved and reloaded Hammerspoon.")
            : T("已写入设置；Hammerspoon 未响应重载，请手动 Reload Config。", "Saved; Hammerspoon did not reload, choose Reload Config.")
    }
}
