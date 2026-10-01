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
  Initials --ui-self-test DIR            offscreen UI checks (isolated INITIALS_SUPPORT_DIR only)
  Initials --control-self-test [SECONDS] pause/status channel only (isolated INITIALS_SUPPORT_DIR only)
"""
// Anything unrecognised exits here: a stray second copy would fight the running one for the keys.
let knownFlags: Set<String> = ["--help", "-h", "--version", "--background", "--simulate", "--snapshot", "--settings",
                               "--picker", "--right", "--dark", "--login-item-status", "--ui-self-test", "--control-self-test"]
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
// SMAppService.mainApp has to run as this bundle, so `initials login` asks this binary. Read only.
if arguments.contains("--login-item-status") {
    let status = SMAppService.mainApp.status
    let name: String
    switch status {
    case .enabled: name = "enabled"
    case .notRegistered: name = "notRegistered"
    case .requiresApproval: name = "requiresApproval"
    case .notFound: name = "notFound"
    @unknown default: name = "unknown"
    }
    let data = try! JSONSerialization.data(withJSONObject: ["openAtLogin": status == .enabled, "status": name], options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
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
