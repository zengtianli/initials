import Foundation

/// A portable configuration is the same JSON as config.json. Only explicit file
/// imports require the complete shape, so an unrelated JSON cannot erase settings.
enum ConfigTransfer {
    struct MissingApp {
        let side: Side
        let letter: String
        let name: String
    }

    struct Imported {
        var config: Config
        var missing: [MissingApp]
    }

    struct Invalid: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    static var backup: URL { backupURL(for: Paths.config) }

    static func backupURL(for configURL: URL) -> URL {
        configURL.deletingLastPathComponent().appendingPathComponent("config-before-import.json")
    }

    static func read(from url: URL,
                     resolve: (Binding) -> URL? = AppCatalog.migrationURL) throws -> Imported {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["right"] is [String: Any], root["left"] is [String: Any], root["version"] != nil else {
            throw Invalid(reason: T("这不是 Initials 配置文件（需包含 version、right 和 left）。",
                                    "Not an Initials configuration (version, right and left are required)."))
        }
        var config = try JSONDecoder().decode(Config.self, from: data)
        guard config.version == 1 else {
            throw Invalid(reason: T("不支持此配置版本，请更新 Initials 后重试。",
                                    "Unsupported configuration version; update Initials and try again."))
        }
        guard config.doubleTapSeconds.isFinite, config.doubleTapSeconds > 0,
              config.pickerTimeoutSeconds.isFinite, config.pickerTimeoutSeconds > 0 else {
            throw Invalid(reason: T("配置中的双击间隔和面板超时必须大于零。",
                                    "Double-tap interval and picker timeout must be positive."))
        }
        // Validate everything before resolving apps or writing any files.
        for side in Side.allCases {
            for (letter, binding) in config.side(side).bindings {
                guard Config.normalizedLetter(letter) == letter,
                      !binding.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw Invalid(reason: T("配置中有无效字母或空的 App 名称。",
                                            "Configuration contains an invalid letter or an empty app name."))
                }
            }
        }
        var missing: [MissingApp] = []
        for side in Side.allCases {
            // Include the independent left table even while it shares the right one.
            for (letter, binding) in config.side(side).bindings.sorted(by: { $0.key < $1.key }) {
                if let local = resolve(binding) {
                    var relocated = binding
                    relocated.path = local.path
                    config.update(side) { $0.bindings[letter] = relocated }
                } else {
                    missing.append(MissingApp(side: side, letter: letter, name: binding.name))
                }
            }
        }
        return Imported(config: config, missing: missing)
    }

    static func export(_ config: Config, to url: URL) throws {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        let protected = [Paths.config, Paths.status, backup].map { $0.resolvingSymlinksInPath().standardizedFileURL }
        guard !protected.contains(target) else {
            throw Invalid(reason: T("请选择单独的导出文件，不要覆盖正在使用的配置或状态文件。",
                                    "Choose a separate export file, rather than an active config or status file."))
        }
        try ConfigStore.save(config, to: url)
    }

    /// One previous configuration, byte-for-byte (even if corrupt), for recovery.
    /// If the backup cannot be written, leave the current configuration untouched.
    @discardableResult
    static func apply(_ imported: Imported, to url: URL = Paths.config) throws -> URL? {
        if FileManager.default.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            if (try? JSONDecoder().decode(Config.self, from: old)) == imported.config { return nil }
            let backup = backupURL(for: url)
            try old.write(to: backup, options: .atomic)
            try ConfigStore.save(imported.config, to: url)
            return backup
        }
        try ConfigStore.save(imported.config, to: url)
        return nil
    }
}
