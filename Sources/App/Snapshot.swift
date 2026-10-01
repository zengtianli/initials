import AppKit

/// `--snapshot out.png --settings right|left [--dark]` or `--snapshot out.png --picker [--right] [--dark]`:
/// renders offscreen from the config in `$INITIALS_SUPPORT_DIR` and exits. Nothing is
/// shown, activated, intercepted or saved.
enum Snapshot {
    static func run(to url: URL, args: [String]) {
        NSApp.setActivationPolicy(.prohibited)
        let config = (try? ConfigStore.load()) ?? Config()
        let appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        do {
            if let i = args.firstIndex(of: "--settings") {
                let side = i + 1 < args.count ? Side(rawValue: args[i + 1]) ?? .right : .right
                let controller = SettingsWindowController(config: config)
                try controller.snapshot(side: side, to: url, appearance: appearance)
            } else {
                let panel = PickerPanel()
                let side: Side = args.contains("--right") ? .right : .left
                try panel.snapshot(PickerPanel.entries(config: config, side: side, running: RunningApp.current()),
                                   to: url, appearance: appearance)
            }
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
        exit(0)
    }
}
