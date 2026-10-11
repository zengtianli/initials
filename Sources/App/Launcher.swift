import AppKit

/// Turns a letter into an app switch. All work happens on the main queue,
/// outside the event tap callback.
enum Launcher {
    /// Verification runs log actions instead of touching other apps.
    static var dryRun = false
    static var onDryRun: ((String) -> Void)?
    /// Isolated acceptance observes the actual resolved dispatch, without opening other apps.
    static var onResolved: ((ResolvedAction) -> Void)?
    static var onActionError: ((String) -> Void)?

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
        case .execute(let action):
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let resolved = try ActionResolver.resolve(action)
                    DispatchQueue.main.async {
                        if let observer = onResolved { observer(resolved) } else { execute(resolved) }
                    }
                } catch { DispatchQueue.main.async {
                    if let observer = onActionError { observer(error.localizedDescription) } else { ActionFeedback.show(error.localizedDescription) }
                } }
            }
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

    private static func execute(_ action: ResolvedAction) {
        switch action {
        case .open(let url):
            if !NSWorkspace.shared.open(url) { ActionFeedback.show(T("无法打开：", "Could not open: ") + action.target) }
        case .reveal(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .shortcut(let name):
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            task.arguments = ["run", name]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.terminationHandler = { task in
                if task.terminationStatus != 0 { DispatchQueue.main.async { ActionFeedback.show(T("快捷指令未能完成：", "The shortcut did not complete: ") + name) } }
            }
            do { try task.run() } catch { ActionFeedback.show(error.localizedDescription) }
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
