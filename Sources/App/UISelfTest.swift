import AppKit

/// Runs real AppKit views without starting the app lifecycle or ordering a window in.
enum UISelfTest {
    /// Self-tests save and write status, so they refuse to run against the real support folder.
    static func requireIsolatedSupport(_ flag: String) {
        guard let isolated = ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"],
              !isolated.isEmpty,
              URL(fileURLWithPath: isolated).standardizedFileURL != FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("cyou.tianli.initials").standardizedFileURL else {
            fputs("\(flag) requires an isolated INITIALS_SUPPORT_DIR\n", stderr)
            exit(2)
        }
    }

    static func run(to directory: URL) -> Never {
        requireIsolatedSupport("--ui-self-test")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var config = Config()
            config.right.bindings = [
                "c": Binding(name: "Calendar", bundleID: "com.apple.iCal", path: nil),
                "f": Binding(name: "Finder", bundleID: "com.apple.finder", path: nil),
            ]
            let settings = SettingsWindowController(config: config)
            var checks = try settings.checkOffscreenInteractions(to: directory)
            AppLifecycleUI.install(name: "Initials", configuration: nil,
                                   updateSource: .manifest(URL(string: "https://initials.tianli.cyou/updates.json")!))
            checks.merge(try AppLifecycleUI.shared.offscreenSnapshot(to: directory.appendingPathComponent("updates.png"))) { _, value in value }
            try checkCloudNotifications(to: directory, checks: &checks)

            let panel = PickerPanel()
            let entries = (0..<14).map { index in
                PickerPanel.Entry(letter: String(UnicodeScalar(97 + index)!), title: "Fixture \(index)", icon: nil, pinned: index < 2)
            }
            try panel.snapshot(entries, to: directory.appendingPathComponent("picker-populated.png"), appearance: NSAppearance(named: .aqua))
            let labels = text(in: panel.contentView!)
            checks["picker_populated_refresh"] = entries.allSatisfy { labels.contains($0.title) }
                && panel.contentView!.bounds.width > 500 && panel.contentView!.bounds.height > 100
            try panel.snapshot([], to: directory.appendingPathComponent("picker-empty.png"), appearance: NSAppearance(named: .aqua))
            let emptyLabels = text(in: panel.contentView!)
            checks["picker_empty_refresh"] = !emptyLabels.contains("Fixture 0")
                && emptyLabels.contains(T("还没有可切换的 app：在设置里给字母指定 app。", "Nothing to switch to yet: pin apps to letters in Settings."))
            checks["picker_never_accepts_focus"] = !panel.canBecomeKey && !panel.canBecomeMain && !panel.isVisible
            panel.close()
            checks["picker_closed"] = !panel.isVisible && !panel.isKeyWindow && !panel.isMainWindow
            checks["no_application_lifecycle"] = app.delegate == nil && app.activationPolicy() == .prohibited
            for file in ["settings-shared.png", "settings-right.png", "picker-populated.png", "picker-empty.png"] {
                let data = try Data(contentsOf: directory.appendingPathComponent(file))
                let bitmap = NSBitmapImageRep(data: data)
                checks["render_" + file] = data.count > 1000 && (bitmap?.pixelsWide ?? 0) > 500 && (bitmap?.pixelsHigh ?? 0) > 100
            }
            let passed = checks.values.allSatisfy { $0 }
            let report: [String: Any] = ["passed": passed, "checks": checks, "method": "in-process AppKit offscreen; direct action calls; no synthesized input"]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("ui-self-test.json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            exit(passed ? 0 : 1)
        } catch {
            fputs("UI self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func text(in view: NSView) -> [String] {
        (view as? NSTextField).map { [$0.stringValue] } ?? []
            + view.subviews.flatMap { text(in: $0) }
    }

    private static func checkCloudNotifications(to directory: URL, checks: inout [String: Bool]) throws {
        let cloud = directory.appendingPathComponent("fixture-cloud", isDirectory: true)
        setenv("INITIALS_ICLOUD_DIR", cloud.path, 1)
        defer { unsetenv("INITIALS_ICLOUD_DIR") }
        try CloudSyncStore.setEnabled(true)
        let controller = CloudSyncController()
        var updates = 0
        controller.onUpdate = { _ in updates += 1 }
        func waitFor(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(8)
            while !predicate() && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            return predicate()
        }
        controller.start()
        checks["icloud_background_initial_sync"] = waitFor { updates > 0 && FileManager.default.fileExists(atPath: cloud.appendingPathComponent("config.json").path) }
        var remote = try ConfigStore.load()
        remote.pickerTimeoutSeconds = 9
        let cloudURL = cloud.appendingPathComponent("config.json")
        let beforeUpdates = updates
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: cloudURL, options: [], error: &coordinationError) { url in
            do { try ConfigStore.save(remote, to: url) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        checks["icloud_remote_notification_applies_without_polling"] = waitFor {
            updates > beforeUpdates && (try? ConfigStore.load().pickerTimeoutSeconds) == 9
        }
        let written = try Data(contentsOf: cloudURL)
        try CloudSyncStore.setEnabled(false)
        controller.request()
        let offUpdates = updates
        checks["icloud_disable_keeps_files"] = waitFor { updates > offUpdates }
            && FileManager.default.fileExists(atPath: Paths.config.path)
        let after = try Data(contentsOf: cloudURL)
        checks["icloud_disable_preserves_cloud"] = written == after
    }
}
