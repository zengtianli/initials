import AppKit

/// Runs real AppKit views without starting the app lifecycle or ordering a window in.
enum UISelfTest {
    static func run(to directory: URL) -> Never {
        guard let isolated = ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"],
              !isolated.isEmpty,
              URL(fileURLWithPath: isolated).standardizedFileURL != FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("cyou.tianli.initials").standardizedFileURL else {
            fputs("--ui-self-test requires an isolated INITIALS_SUPPORT_DIR\n", stderr)
            exit(2)
        }
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
}
