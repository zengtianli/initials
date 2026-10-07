import AppKit
import ServiceManagement

let arguments = CommandLine.arguments
let appUsage = """
Initials — the menu-bar app. Settings and status for scripts and agents: the `initials` command.

  Initials --background                  start without opening Settings (login, relaunch)
  Initials --version                     print the version
  Initials --simulate right:m,left:s     print what each letter would do now; nothing is done
  Initials --snapshot out.png --settings right|left [--dark]   offscreen render, then exit
  Initials --snapshot out.png --picker [--right] [--dark]
  Initials --login-item-status           print whether Initials opens at login (JSON), then exit
  Initials --login-item-set on|off       switch it (what `initials login on|off` runs), print the result, then exit
  Initials --ui-self-test DIR            offscreen UI checks (isolated INITIALS_SUPPORT_DIR only)
  Initials --control-self-test [SECONDS] pause/status channel only (isolated INITIALS_SUPPORT_DIR only)
  Initials --background-measure -lane_quiet YES   measurement lane only: private support path, no key tap,
                                         no menu-bar item, no update or iCloud work; reports readiness
"""
// Anything unrecognised exits here: a stray second copy would fight the running one for the keys.
let knownFlags: Set<String> = ["--help", "-h", "--version", "--background", "--simulate", "--snapshot", "--settings",
                               "--picker", "--right", "--dark", "--login-item-status", "--login-item-set", "--ui-self-test", "--control-self-test",
                               QuietMeasure.flag]
if arguments.contains("--help") || arguments.contains("-h") {
    print(appUsage)
    exit(0)
}
if arguments.contains("--version") {
    print("Initials \(appVersion)")
    exit(0)
}
if let unknown = arguments.dropFirst().first(where: { $0.hasPrefix("--") && !knownFlags.contains($0) }) {
    fputs("Initials: unknown option \(unknown)\n\n\(appUsage)\n", stderr)
    exit(2)
}
// SMAppService.mainApp has to run as this bundle, so `initials login` asks this binary.
func printLoginItem(error: String? = nil) -> Bool {
    let status = SMAppService.mainApp.status
    let name: String
    switch status {
    case .enabled: name = "enabled"
    case .notRegistered: name = "notRegistered"
    case .requiresApproval: name = "requiresApproval"
    case .notFound: name = "notFound"
    @unknown default: name = "unknown"
    }
    var answer: [String: Any] = ["openAtLogin": status == .enabled, "status": name]
    if let error { answer["error"] = error }
    let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    return status == .enabled
}
// Read only.
if arguments.contains("--login-item-status") {
    _ = printLoginItem()
    exit(0)
}
// The Settings checkbox's two calls. Exit 0 only when macOS then reports the requested state.
if let i = arguments.firstIndex(of: "--login-item-set") {
    guard i + 1 < arguments.count, ["on", "off"].contains(arguments[i + 1]) else {
        fputs("--login-item-set needs on or off\n", stderr)
        exit(2)
    }
    // A test copy must never register itself as the owner's login item.
    guard ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"] == nil else {
        fputs("Initials: an isolated run (INITIALS_SUPPORT_DIR) never changes the login item\n", stderr)
        exit(1)
    }
    let want = arguments[i + 1] == "on"
    var failure: String?
    do {
        if want { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
        failure = error.localizedDescription
    }
    exit(printLoginItem(error: failure) == want ? 0 : 1)
}
// `--simulate right:d,left:m`: print what each letter would do right now, without doing it.
if let i = arguments.firstIndex(of: "--simulate"), i + 1 < arguments.count {
    let config = (try? ConfigStore.load()) ?? Config()
    Launcher.dryRun = true
    Launcher.onDryRun = { print($0) }
    for spec in arguments[i + 1].split(separator: ",") {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 2, let side = Side(rawValue: parts[0]), let letter = Config.normalizedLetter(parts[1]) else { continue }
        print("\(side.rawValue) \(letter): ", terminator: "")
        Launcher.perform(letter: letter, side: side, config: config)
    }
    exit(0)
}
// The measurement lane's copy: entered before the one-copy check, and it never builds the app delegate.
if arguments.contains(QuietMeasure.flag) {
    MainActor.assumeIsolated { QuietMeasure.run() }
}
for flag in ["--ui-self-test", "--control-self-test"] where arguments.contains(flag) {
    UISelfTest.requireIsolatedSupport(flag)
}
// One copy per support folder: a second would double-handle keys. The folder's status.json names the
// running copy, so a self-test in its own isolated folder or a --snapshot render never blocks the real app.
if !arguments.contains("--snapshot"), let other = RuntimeStatus.live(),
   other.pid != ProcessInfo.processInfo.processIdentifier {
    fputs("Initials is already running for \(Paths.supportDirectory.path) (pid \(other.pid)); not starting another copy.\n", stderr)
    exit(1)
}
// Keep the acceptance process separate from AppDelegate, EventTap and login/menu setup.
if let i = arguments.firstIndex(of: "--ui-self-test") {
    guard i + 1 < arguments.count else {
        fputs("--ui-self-test requires an output directory\n", stderr)
        exit(2)
    }
    UISelfTest.run(to: URL(fileURLWithPath: arguments[i + 1], isDirectory: true))
}
if let i = arguments.firstIndex(of: "--control-self-test") {
    ControlSelfTest.run(seconds: i + 1 < arguments.count ? Double(arguments[i + 1]) ?? 20 : 20)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
signal(SIGTERM) { _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
app.run()
