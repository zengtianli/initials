import AppKit
import CoreServices
import UniformTypeIdentifiers

enum ActionKind: String, Codable, CaseIterable {
    case showDownloads = "show-downloads", openLastDownload = "open-last-download"
    case revealLastDownload = "reveal-last-download", openLastScreenshot = "open-last-screenshot"
    case openFolder = "open-folder", openFile = "open-file", openURL = "open-url", runShortcut = "run-shortcut"
    var title: String { T(zh, en) }
    var zh: String {
        switch self {
        case .showDownloads: return "显示 Downloads"
        case .openLastDownload: return "打开最近下载项"
        case .revealLastDownload: return "在 Finder 中选中最近下载项"
        case .openLastScreenshot: return "打开最新截图"
        case .openFolder: return "打开文件夹"
        case .openFile: return "打开文件"
        case .openURL: return "打开网址"
        case .runShortcut: return "运行快捷指令"
        }
    }
    var en: String {
        switch self {
        case .showDownloads: return "Show Downloads"
        case .openLastDownload: return "Open Last Downloaded Item"
        case .revealLastDownload: return "Reveal Last Downloaded Item"
        case .openLastScreenshot: return "Open Latest Screenshot"
        case .openFolder: return "Open Folder"
        case .openFile: return "Open File"
        case .openURL: return "Open URL"
        case .runShortcut: return "Run Shortcut"
        }
    }
    var needsTarget: Bool { [.openFolder, .openFile, .openURL, .runShortcut].contains(self) }
    /// What Settings offers. The Mac App Store build leaves out the latest-screenshot action: the screenshot
    /// folder (Desktop, or wherever the system setting points) is outside the App Sandbox.
    static var offered: [ActionKind] {
        #if APP_STORE
        return allCases.filter { $0 != .openLastScreenshot }
        #else
        return allCases
        #endif
    }
    var symbol: String {
        switch self {
        case .showDownloads, .openFolder: return "folder"
        case .openLastDownload: return "arrow.down.doc"
        case .revealLastDownload: return "doc.viewfinder"
        case .openLastScreenshot: return "photo"
        case .openFile: return "doc"
        case .openURL: return "globe"
        case .runShortcut: return "bolt"
        }
    }
    var hint: String {
        switch self {
        case .showDownloads: return T("在 Finder 中打开下载文件夹。", "Open your Downloads folder in Finder.")
        case .openLastDownload: return T("用默认应用打开最近加入 Downloads 的完整项目。", "Open the most recently added completed item in Downloads with its default app.")
        case .revealLastDownload: return T("在 Finder 中选中最近下载的项目，方便改名、拖动或发送。", "Select the latest download in Finder to rename, drag or share it.")
        case .openLastScreenshot: return T("打开系统截图目录中的最新截图。", "Open the latest screenshot in your system screenshot folder.")
        case .openFolder: return T("选择一个文件夹，每次在 Finder 中打开。", "Choose a folder to open in Finder.")
        case .openFile: return T("选择一个文件，用默认应用打开。", "Choose a file to open with its default app.")
        case .openURL: return T("输入完整网址，也支持应用的深层链接。", "Enter a full URL or an app deep link.")
        case .runShortcut: return T("输入 macOS「快捷指令」中已有指令的名称。", "Enter the name of an existing macOS shortcut.")
        }
    }
}

struct LetterAction: Codable, Equatable {
    var kind: ActionKind
    var target: String?
    init(kind: ActionKind, target: String? = nil) throws {
        self.kind = kind
        let value = target?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.target = value?.isEmpty == false ? value : nil
        try validate()
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(kind: c.decode(ActionKind.self, forKey: .kind), target: c.decodeIfPresent(String.self, forKey: .target))
    }
    func validate() throws {
        guard kind.needsTarget == (target != nil) else { throw ActionError(T("此动作的目标参数不完整或多余。", "Missing or unexpected action target.")) }
        if kind == .openFolder || kind == .openFile {
            guard let target, target.hasPrefix("/") || target.hasPrefix("~/") else { throw ActionError(T("请选择绝对路径或 ~/ 开头的路径。", "Use an absolute path or a path starting with ~/.")) }
        }
        if kind == .openURL {
            guard let target, let url = URL(string: target), let scheme = url.scheme, !scheme.isEmpty,
                  !target.contains(where: { $0.isWhitespace }), scheme.lowercased() != "file",
                  !["http", "https"].contains(scheme.lowercased()) || url.host?.isEmpty == false else {
                throw ActionError(T("请输入完整网址，例如 https://example.com。", "Enter a full URL, such as https://example.com."))
            }
        }
    }
    var binding: Binding { Binding(name: kind.en, action: self) }
    var displayName: String {
        guard let target else { return kind.title }
        let value = [.openFile, .openFolder].contains(kind) ? (target as NSString).lastPathComponent : target
        return kind.title + " · " + value
    }
    var location: String {
        if let target { return target }
        guard kind == .openLastScreenshot else { return "~/Downloads" }
        #if APP_STORE
        return ActionResolver.unavailable
        #else
        return ActionResolver.screenshotDirectory.path
        #endif
    }
    var icon: NSImage? { NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.title) }
}

struct ActionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum ResolvedAction: Equatable {
    case open(URL), reveal(URL), shortcut(String)
    var target: String {
        switch self {
        case .open(let url), .reveal(let url): return url.isFileURL ? url.path : url.absoluteString
        case .shortcut(let name): return name
        }
    }
    var verb: String {
        switch self { case .open: return "open"; case .reveal: return "reveal"; case .shortcut: return "run-shortcut" }
    }
}

/// No watcher, polling or recursive scan: resolve only when requested.
enum ActionResolver {
    struct Item { var url: URL; var added: Date?; var created: Date?; var screenshot = false }
    private static func isolatedDirectory(_ key: String) -> URL? {
        guard ProcessInfo.processInfo.environment["INITIALS_SUPPORT_DIR"] != nil,
              let path = ProcessInfo.processInfo.environment[key] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    static var downloads: URL { isolatedDirectory("INITIALS_ACTION_DOWNLOADS_DIR") ?? Paths.userHome.appendingPathComponent("Downloads", isDirectory: true) }
    #if APP_STORE
    static var unavailable: String { T("Mac App Store 版不提供此动作", "Not available in the Mac App Store version") }
    /// Never read in this build: `resolve` refuses the screenshot action before it would be.
    static var screenshotDirectory: URL { Paths.userHome.appendingPathComponent("Desktop", isDirectory: true) }
    #else
    static var screenshotDirectory: URL {
        if let isolated = isolatedDirectory("INITIALS_ACTION_SCREENSHOTS_DIR") { return isolated }
        let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
    #endif
    static func portablePath(_ url: URL) -> String {
        let home = Paths.userHome.path
        return url.path.hasPrefix(home + "/") ? "~" + String(url.path.dropFirst(home.count)) : url.path
    }
    /// `~/…` → the real home folder (`expandingTildeInPath` gives the container in the App Sandbox).
    static func expand(_ path: String) -> String {
        #if APP_STORE
        if path == "~" { return Paths.userHome.path }
        if path.hasPrefix("~/") { return Paths.userHome.path + String(path.dropFirst(1)) }
        #endif
        return (path as NSString).expandingTildeInPath
    }
    static func latest(_ items: [Item], screenshotsOnly: Bool = false) -> URL? {
        let incomplete = Set(["download", "crdownload", "part", "partial", "tmp", "temp", "icloud"])
        return items.filter {
            !$0.url.lastPathComponent.hasPrefix(".") && !incomplete.contains($0.url.pathExtension.lowercased()) && (!screenshotsOnly || $0.screenshot)
        }.sorted {
            let a = $0.added ?? $0.created ?? .distantPast, b = $1.added ?? $1.created ?? .distantPast
            return a == b ? $0.url.path < $1.url.path : a > b
        }.first?.url
    }
    static func items(in directory: URL) throws -> [Item] {
        let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey, .contentTypeKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let isImage = values.contentType?.conforms(to: .image) == true
            let metadata = isImage ? MDItemCreate(kCFAllocatorDefault, url.path as CFString) : nil
            let captured = metadata.flatMap { MDItemCopyAttribute($0, "kMDItemIsScreenCapture" as CFString) as? NSNumber }?.boolValue == true
            let named = ["Screenshot ", "Screen Shot ", "截屏", "屏幕快照"].contains { url.lastPathComponent.hasPrefix($0) }
            return Item(url: url, added: values.addedToDirectoryDate, created: values.creationDate,
                        screenshot: values.isDirectory != true && isImage && (captured || named))
        }
    }
    static func resolve(_ action: LetterAction, downloads: URL = downloads, screenshots: URL = screenshotDirectory,
                        read: (URL) throws -> [Item] = items) throws -> ResolvedAction {
        try action.validate()
        #if APP_STORE
        guard action.kind != .openLastScreenshot else { throw ActionError(unavailable) }
        #endif
        switch action.kind {
        case .showDownloads: return try existing(downloads, directory: true)
        case .openFolder, .openFile:
            let path = expand(action.target!)
            #if APP_STORE
            return try existing(try FileGrants.url(for: path), directory: action.kind == .openFolder)
            #else
            return try existing(URL(fileURLWithPath: path), directory: action.kind == .openFolder)
            #endif
        case .openURL: return .open(URL(string: action.target!)!)
        case .runShortcut: return .shortcut(action.target!)
        case .openLastDownload, .revealLastDownload, .openLastScreenshot:
            let screenshotsOnly = action.kind == .openLastScreenshot
            guard let url = latest(try read(screenshotsOnly ? screenshots : downloads), screenshotsOnly: screenshotsOnly) else {
                throw ActionError(screenshotsOnly ? T("截图目录中没有可打开的截图。", "No screenshot is available in your screenshot folder.") : T("Downloads 中没有已完成的下载项目。", "No completed download is available in Downloads."))
            }
            return action.kind == .revealLastDownload ? .reveal(url) : .open(url)
        }
    }
    private static func existing(_ url: URL, directory: Bool) throws -> ResolvedAction {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue == directory else {
            throw ActionError(T("目标不存在或类型不符：", "Target is missing or has the wrong type: ") + url.path)
        }
        return .open(url)
    }
}
