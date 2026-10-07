import AppKit

/// `Initials --background-measure -lane_quiet YES`: the cold-launch probe of the shared measurement lane, which
/// starts a re-signed copy of the installed app five times while the owner's Initials keeps running.
///
/// It loads the configuration from a private support path, applies it to a key engine and reports readiness.
/// Nothing here reaches outside the process: no status item, no key tap, no pause channel, no update or iCloud
/// work, no status file. main.swift enters it before the one-copy check, so the app delegate and everything it
/// owns are never created. Without the lane's quiet flag it refuses to start.
enum QuietMeasure {
    static let flag = "--background-measure"
    @MainActor private static var engine = KeyEngine()

    @MainActor static func run() -> Never {
        guard LaneSignal.quiet else {
            fputs("Initials: \(flag) is the measurement lane's entry and needs -lane_quiet YES; nothing was started.\n", stderr)
            exit(2)
        }
        // The existing isolation seam (Paths.supportDirectory). A per-process path that is never created:
        // the load below finds no file and returns the defaults, and nothing in this path writes.
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("initials-measure-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        setenv("INITIALS_SUPPORT_DIR", support.path, 1)

        let app = NSApplication.shared
        LaneSignal.enterQuietIfAsked()
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated {
                let config = (try? ConfigStore.load()) ?? Config()
                engine.right = config.trigger(for: .right)
                engine.left = config.trigger(for: .left)
                engine.doubleTap = config.doubleTapSeconds
                LaneSignal.ready("menubar")
            }
        }
        // The lane ends its copy itself; a stray one must not stay behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { exit(0) }
        app.run()
        exit(0)
    }
}
