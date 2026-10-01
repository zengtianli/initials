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
    let candidates = cycleCandidates(letter: letter, running: running)
    guard !candidates.isEmpty else { return .nothing }
    if let i = candidates.firstIndex(where: { $0.pid == frontmostPID }) {
        if candidates.count == 1 { return options.hideIfFrontmost ? .hide(candidates[i]) : .nothing }
        return .activate(candidates[(i + 1) % candidates.count])
    }
    return .activate(candidates[0])
}

/// Running apps whose name starts with the letter, in the order an unpinned letter cycles them.
func cycleCandidates(letter: String, running: [RunningApp]) -> [RunningApp] {
    running.filter { $0.name.lowercased().hasPrefix(letter) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

extension AppAction {
    /// Stable verb for dry runs and `initials preview --json`.
    var verb: String {
        switch self {
        case .open: return "open"
        case .activate: return "activate"
        case .hide: return "hide"
        case .nothing: return "nothing"
        }
    }

    /// The app the action targets, if any.
    var appName: String? {
        switch self {
        case .open(let binding): return binding.name
        case .activate(let app), .hide(let app): return app.name
        case .nothing: return nil
        }
    }

    /// "open Music", "hide Mail", "nothing" (the `--simulate` line).
    var summary: String { appName.map { "\(verb) \($0)" } ?? verb }
}

func matches(_ app: RunningApp, _ binding: Binding) -> Bool {
    if let id = binding.bundleID, let appID = app.bundleID { return id == appID }
    if let path = binding.path, let appPath = app.path { return path == appPath }
    return app.name.caseInsensitiveCompare(binding.name) == .orderedSame
}
