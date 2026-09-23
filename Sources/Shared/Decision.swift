import Foundation

/// A snapshot of one running app (regular, Dock-visible apps only).
struct RunningApp: Equatable {
    var pid: Int32
    var name: String
    var bundleID: String?
    var path: String?
}

enum AppAction: Equatable {
    /// Open (launch or bring forward) a pinned app.
    case open(Binding)
    case activate(RunningApp)
    case hide(RunningApp)
    case nothing
}

/// What a letter does, given the current apps. Same rules as rcmd:
/// pinned → open it, or hide it when it is already in front;
/// unpinned → cycle through running apps whose name starts with the letter.
func decide(letter: String, bindings: [String: Binding], options: SideConfig,
            running: [RunningApp], frontmostPID: Int32?) -> AppAction {
    if let binding = bindings[letter] {
        let app = running.first { matches($0, binding) }
        if let app, app.pid == frontmostPID, options.hideIfFrontmost { return .hide(app) }
        return .open(binding)
    }
    guard options.cycleUnbound else { return .nothing }
    let candidates = running
        .filter { $0.name.lowercased().hasPrefix(letter) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    guard !candidates.isEmpty else { return .nothing }
    if let i = candidates.firstIndex(where: { $0.pid == frontmostPID }) {
        if candidates.count == 1 { return options.hideIfFrontmost ? .hide(candidates[i]) : .nothing }
        return .activate(candidates[(i + 1) % candidates.count])
    }
    return .activate(candidates[0])
}

func matches(_ app: RunningApp, _ binding: Binding) -> Bool {
    if let id = binding.bundleID, let appID = app.bundleID { return id == appID }
    if let path = binding.path, let appPath = app.path { return path == appPath }
    return app.name.caseInsensitiveCompare(binding.name) == .orderedSame
}
