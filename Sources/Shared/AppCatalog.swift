import AppKit

/// Finds installed apps and turns a name, path or bundle identifier into a binding.
enum AppCatalog {
    static var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/Applications/Utilities", "/System/Applications",
                "/System/Applications/Utilities", "/System/Library/CoreServices"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            + [home.appendingPathComponent("Applications", isDirectory: true)]
    }

    static func binding(for url: URL) -> Binding? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return Binding(name: name, bundleID: bundle.bundleIdentifier, path: url.path)
    }

    /// Apps in the standard folders and one level of subfolders, sorted by name.
    static func installed() -> [Binding] {
        var seen = Set<String>(), result: [Binding] = []
        let fm = FileManager.default
        func visit(_ dir: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { return }
            for url in items {
                if url.pathExtension == "app" {
                    if let b = binding(for: url), seen.insert(b.bundleID ?? url.path).inserted { result.append(b) }
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(url, depth: depth - 1)
                }
            }
        }
        for dir in searchDirectories { visit(dir, depth: 1) }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Accepts "/path/To.app", "com.example.id", "Music" or "Music.app".
    static func resolve(_ query: String, installed: [Binding]? = nil) -> Binding? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        if q.hasPrefix("/") || q.hasPrefix("~") {
            return binding(for: URL(fileURLWithPath: (q as NSString).expandingTildeInPath))
        }
        if q.contains("."), !q.contains(" "), !q.lowercased().hasSuffix(".app"),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: q) {
            return binding(for: url)
        }
        let bare = q.lowercased().hasSuffix(".app") ? String(q.dropLast(4)) : q
        for dir in searchDirectories {
            let url = dir.appendingPathComponent(bare + ".app")
            if FileManager.default.fileExists(atPath: url.path), let b = binding(for: url) { return b }
        }
        let all = installed ?? self.installed()
        return all.first { $0.name.caseInsensitiveCompare(bare) == .orderedSame }
            ?? all.first { ($0.path as NSString?)?.lastPathComponent.caseInsensitiveCompare(bare + ".app") == .orderedSame }
    }

    /// The saved location first (what the user picked, e.g. /Applications/Safari.app rather
    /// than its sealed system copy); the bundle identifier finds apps that moved.
    static func url(for binding: Binding) -> URL? {
        if let path = binding.path, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        if let id = binding.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        return resolve(binding.name).flatMap { $0.path.map { URL(fileURLWithPath: $0) } }
    }
}
