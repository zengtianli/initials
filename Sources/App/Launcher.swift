import AppKit

/// Turns a letter into an app switch. All work happens on the main queue,
/// outside the event tap callback.
enum Launcher {
    /// Verification runs log actions instead of touching other apps.
    static var dryRun = false
    static var onDryRun: ((String) -> Void)?

    static func perform(letter: String, side: Side, config: Config) {
        let action = decide(letter: letter, bindings: config.bindings(for: side), options: config.side(side),
                            running: RunningApp.current(), frontmostPID: RunningApp.frontmostPID)
        perform(action)
    }

    static func perform(_ action: AppAction) {
        if dryRun {
            onDryRun?(action.summary)
            return
        }
        switch action {
        case .nothing:
            break
        case .hide(let app):
            NSRunningApplication(processIdentifier: app.pid)?.hide()
        case .open(let binding):
            guard let url = AppCatalog.url(for: binding) else { NSSound.beep(); return }
            open(url)
        case .activate(let app):
            if let path = app.path {
                open(URL(fileURLWithPath: path))
            } else {
                NSRunningApplication(processIdentifier: app.pid)?.activate()
            }
        }
    }

    /// Opening the bundle works whether or not the app runs, and macOS grants
    /// activation to it (a plain `activate()` from a background agent may be refused).
    private static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if error != nil { DispatchQueue.main.async { NSSound.beep() } }
        }
    }
}
