// Mac App Store build only: the App Sandbox reaches a file or folder outside the container only after the user
// picks it in an open panel. The pick is kept as an app-scoped security bookmark so a letter still opens it
// after a relaunch.
#if APP_STORE
import Foundation

enum FileGrants {
    /// Path → bookmark, beside config.json. config.json itself stays the same portable file as in the
    /// direct-download build.
    static var file: URL { Paths.supportDirectory.appendingPathComponent("file-grants.json") }
    private static let lock = NSLock()
    /// Granted locations in use by this process: access starts once per path and lasts until the app quits,
    /// so repeated presses never pile up sandbox extensions.
    private static var active: [String: URL] = [:]

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    private static func load() -> [String: Data] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private static func save(_ grants: [String: Data]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(grants).write(to: file, options: .atomic)
    }

    /// Call with the URL an open panel returned.
    static func remember(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
        lock.lock(); defer { lock.unlock() }
        var grants = load()
        grants[key(url)] = bookmark
        try save(grants)
    }

    /// The URL to open for a configured path: the granted location, or the path itself when the sandbox can
    /// already read it (the container, Downloads, system folders).
    static func url(for path: String) throws -> URL {
        let plain = URL(fileURLWithPath: path)
        let id = key(plain)
        lock.lock(); defer { lock.unlock() }
        if let url = active[id] { return url }
        var grants = load()
        if let bookmark = grants[id] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil,
                                  bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() {
                if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
                    grants[id] = fresh
                    try? save(grants)
                }
                active[id] = url
                return url
            }
        }
        if FileManager.default.isReadableFile(atPath: path) { return plain }
        throw ActionError(T("Mac App Store 版需要你授权这个位置：在设置里编辑这个字母，用“选择…”重新选一次。",
                            "The Mac App Store version needs your permission for this location: edit this letter in Settings and pick it again with Choose…"))
    }
}
#endif
