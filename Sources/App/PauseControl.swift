import AppKit

/// Pause from the menu bar or `initials pause|resume`: runtime only, never saved, gone on restart.
/// Every request calls `onChange`, even one that changes nothing, so the status file confirms it.
/// `initials quit` arrives on the same channel and calls `onQuit`.
final class PauseControl: NSObject {
    private(set) var paused = false
    var onChange: (() -> Void)?
    var onQuit: (() -> Void)?

    /// An accessory app is almost never active, and inactive apps receive distributed
    /// notifications late unless they ask for immediate delivery.
    func listen() {
        // The scope is the folder's real path, so the folder must exist before it is computed.
        try? FileManager.default.createDirectory(at: Paths.supportDirectory, withIntermediateDirectories: true)
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(pauseRequested), name: RuntimeControl.pause,
                           object: RuntimeControl.scope, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(resumeRequested), name: RuntimeControl.resume,
                           object: RuntimeControl.scope, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(quitRequested), name: RuntimeControl.quit,
                           object: RuntimeControl.scope, suspensionBehavior: .deliverImmediately)
    }

    func set(_ value: Bool) {
        paused = value
        onChange?()
    }

    @objc private func pauseRequested() { set(true) }
    @objc private func resumeRequested() { set(false) }
    @objc private func quitRequested() { onQuit?() }
}

/// `Initials --control-self-test [seconds]` (isolated `INITIALS_SUPPORT_DIR` only): the real
/// `PauseControl` and status file in a process that never shows anything, never intercepts keys
/// and never becomes active, so acceptance can drive `initials pause|resume|quit|status` end to end.
/// Exits after the given seconds (default 20) or on SIGTERM, removing its own status file.
enum ControlSelfTest {
    static func run(seconds: Double) -> Never {
        UISelfTest.requireIsolatedSupport("--control-self-test")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let control = PauseControl()
        let pid = ProcessInfo.processInfo.processIdentifier
        let publish = {
            RuntimeStatus(pid: pid, accessibilityTrusted: false, tapEnabled: false, paused: control.paused,
                          version: appVersion, updated: Date()).write()
        }
        control.onChange = publish
        let finish: () -> Never = {
            RuntimeStatus.remove(ifOwnedBy: pid)
            exit(0)
        }
        control.onQuit = { finish() }
        control.listen()
        publish()
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { finish() }
        term.resume()
        Timer.scheduledTimer(withTimeInterval: max(1, seconds), repeats: false) { _ in finish() }
        app.run()
        finish()
    }
}
