import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print("Initials \(appVersion)")
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
signal(SIGTERM) { _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
app.run()
