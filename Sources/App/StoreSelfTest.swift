// Mac App Store build only. `Initials --store-self-test`: prints what the App Sandbox lets this build reach,
// as JSON, then exits. Nothing is shown, no key tap is created, no permission is requested and the settings
// file is not changed (one probe file is written beside it and removed).
#if APP_STORE
import AppKit

enum StoreSelfTest {
    static let flag = "--store-self-test"

    static func run() -> Never {
        let environment = ProcessInfo.processInfo.environment
        let support = Paths.supportDirectory
        var report: [String: Any] = [
            "version": appVersion,
            "sandboxContainer": environment["APP_SANDBOX_CONTAINER_ID"] ?? NSNull(),
            "home": NSHomeDirectory(),
            "userHome": Paths.userHome.path,
            "supportDirectory": support.path,
            "downloads": ActionResolver.downloads.path,
            "accessibilityTrusted": EventTap.trusted,
        ]
        // Settings: read what is there, and prove the folder takes a write without touching config.json.
        do {
            let config = try ConfigStore.load()
            report["configExists"] = FileManager.default.fileExists(atPath: Paths.config.path)
            report["configLetters"] = config.right.bindings.count + config.left.bindings.count
        } catch { report["configError"] = error.localizedDescription }
        let probe = support.appendingPathComponent("store-self-test-\(ProcessInfo.processInfo.processIdentifier).json")
        do {
            try ConfigStore.save(Config(), to: probe)
            report["supportWritable"] = try ConfigStore.load(from: probe) == Config()
            try FileManager.default.removeItem(at: probe)
        } catch { report["supportWritable"] = false; report["supportError"] = error.localizedDescription }
        // What a letter can be pinned to, cycle through and open.
        let installed = AppCatalog.installed()
        report["installedApps"] = installed.count
        report["installedSample"] = installed.prefix(5).map(\.name)
        report["finderResolved"] = AppCatalog.resolve("com.apple.finder")?.path ?? NSNull()
        report["runningApps"] = RunningApp.current().count
        report["offeredActions"] = ActionKind.offered.map(\.rawValue)
        // Outside the container and never granted: must be refused, with the message the user would see.
        do {
            _ = try ActionResolver.resolve(try LetterAction(kind: .openFolder, target: "~/Public"))
            report["ungrantedFolder"] = "opened"
        } catch { report["ungrantedFolder"] = error.localizedDescription }
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    }
}
#endif
