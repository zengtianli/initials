import Foundation

/// Uses the user's ordinary iCloud Drive folder. The local config remains the
/// runtime source, so switching apps never waits for a download or a network call.
enum CloudSyncStore {
    struct Preferences: Codable { var enabled = true }
    struct State: Codable { var cloud: Config; var local: Config }
    static var preferencesURL: URL { Paths.supportDirectory.appendingPathComponent("sync-preferences.json") }
    static var stateURL: URL { Paths.supportDirectory.appendingPathComponent("sync-state.json") }
    static var directory: URL? {
        let env = ProcessInfo.processInfo.environment
        if let isolated = env["INITIALS_ICLOUD_DIR"], env["INITIALS_SUPPORT_DIR"] != nil {
            return URL(fileURLWithPath: isolated, isDirectory: true)
        }
        guard env["INITIALS_SUPPORT_DIR"] == nil else { return nil }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.ubiquityIdentityToken != nil,
              FileManager.default.fileExists(atPath: root.path),
              FileManager.default.isUbiquitousItem(at: root) else { return nil }
        return root.appendingPathComponent("Initials", isDirectory: true)
    }
    static var file: URL? { directory?.appendingPathComponent("config.json") }

    static func preferences() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else { return Preferences() }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesURL))
    }

    static func setEnabled(_ enabled: Bool) throws {
        try write(Preferences(enabled: enabled), to: preferencesURL)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if (try? Data(contentsOf: url)) == data { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Three-way merge: edits to different letters/options on offline Macs survive.
    /// For the same field changed on both, this Mac's pending edit wins.
    static func merge(base: Config, local: Config, cloud: Config) -> Config {
        func pick<T: Equatable>(_ base: T, _ local: T, _ cloud: T) -> T { local == base ? cloud : local }
        var result = cloud
        result.doubleTapSeconds = pick(base.doubleTapSeconds, local.doubleTapSeconds, cloud.doubleTapSeconds)
        result.pickerTimeoutSeconds = pick(base.pickerTimeoutSeconds, local.pickerTimeoutSeconds, cloud.pickerTimeoutSeconds)
        for side in Side.allCases {
            let b = base.side(side), l = local.side(side), c = cloud.side(side)
            result.update(side) { r in
                r.enabled = pick(b.enabled, l.enabled, c.enabled)
                r.hold = pick(b.hold, l.hold, c.hold)
                r.doubleTap = pick(b.doubleTap, l.doubleTap, c.doubleTap)
                r.hideIfFrontmost = pick(b.hideIfFrontmost, l.hideIfFrontmost, c.hideIfFrontmost)
                r.cycleUnbound = pick(b.cycleUnbound, l.cycleUnbound, c.cycleUnbound)
                r.useRightBindings = pick(b.useRightBindings, l.useRightBindings, c.useRightBindings)
                for key in Set(b.bindings.keys).union(l.bindings.keys).union(c.bindings.keys) {
                    r.bindings[key] = pick(b.bindings[key], l.bindings[key], c.bindings[key])
                }
            }
        }
        return result
    }

    /// All cloud I/O is coordinated; the app calls this on its background queue.
    /// Fresh installs pull the cloud copy before they can publish defaults.
    static func sync(presenter: NSFilePresenter? = nil) throws -> String {
        guard try preferences().enabled else { return T("iCloud 同步已关闭", "iCloud sync is off") }
        guard let file, let directory else {
            return T("等待 iCloud Drive；本机配置仍可使用", "Waiting for iCloud Drive; local settings still work")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = Paths.supportDirectory.appendingPathComponent("sync.lock")
        try FileManager.default.createDirectory(at: Paths.supportDirectory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        var coordinationError: NSError?
        var operationError: Error?
        var note = T("配置已写入 iCloud Drive，系统将自动同步", "Settings saved in iCloud Drive; macOS handles transfer")
        if FileManager.default.isUbiquitousItem(at: file) {
            try FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: file, options: [], error: &coordinationError) { cloudURL in
            do {
                let local = try ConfigStore.load()
                let previous: State? = FileManager.default.fileExists(atPath: stateURL.path)
                    ? try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) : nil
                let hasCloud = FileManager.default.fileExists(atPath: cloudURL.path)
                    || FileManager.default.fileExists(atPath: cloudURL.deletingLastPathComponent()
                        .appendingPathComponent(".config.json.icloud").path)
                let cloud: Config?
                if hasCloud {
                    // Coordination downloads an evicted iCloud document before reading.
                    _ = try ConfigTransfer.read(from: cloudURL, resolve: { _ in nil })
                    cloud = try ConfigStore.load(from: cloudURL)
                } else { cloud = nil }
                var desired: Config
                if let cloud {
                    if let previous {
                        // Local path relocation must not be mistaken for a user edit.
                        desired = merge(base: previous.local, local: local,
                                        cloud: cloud == previous.cloud ? previous.local : cloud)
                    } else {
                        // First connection: cloud wins existing letters; local-only letters
                        // join it. An empty new Mac cannot wipe the cloud configuration.
                        desired = cloud
                        for side in Side.allCases {
                            for (letter, binding) in local.side(side).bindings where cloud.side(side).bindings[letter] == nil {
                                desired.update(side) { $0.bindings[letter] = binding }
                            }
                        }
                    }
                } else {
                    desired = local
                    // Do not upload brand-new defaults while iCloud is still arriving.
                    if local == Config() && previous == nil {
                        note = T("等待 iCloud 配置；也可添加字母或导入配置", "Waiting for iCloud settings; add letters or import a file")
                        return
                    }
                }
                // Preserve paths in the cloud unless the user changed that binding;
                // normalize only the local runtime copy for this Mac.
                var relocated = desired
                for side in Side.allCases {
                    for (letter, binding) in desired.side(side).bindings {
                        if let url = AppCatalog.migrationURL(for: binding) {
                            var binding = binding; binding.path = url.path
                            relocated.update(side) { $0.bindings[letter] = binding }
                        }
                    }
                }
                guard try ConfigStore.load() == local else {
                    throw ConfigTransfer.Invalid(reason: T("配置刚有变化，稍后自动重试", "Settings changed during sync; will retry"))
                }
                if desired != cloud { try ConfigStore.save(desired, to: cloudURL) }
                if relocated != local {
                    try ConfigTransfer.apply(.init(config: relocated, missing: []))
                }
                try write(State(cloud: desired, local: relocated), to: stateURL)
            } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
        return note
    }
}
