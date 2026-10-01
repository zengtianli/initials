import AppKit

extension RunningApp {
    /// Regular (Dock-visible) apps running now: what unpinned letters cycle through.
    static func current() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map { RunningApp(pid: $0.processIdentifier, name: $0.localizedName ?? "",
                              bundleID: $0.bundleIdentifier, path: $0.bundleURL?.path) }
    }

    static var frontmostPID: Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    /// The app in front, which may be a menu-bar (accessory) app that no letter cycles to.
    static var frontmost: RunningApp? {
        NSWorkspace.shared.frontmostApplication.map {
            RunningApp(pid: $0.processIdentifier, name: $0.localizedName ?? "", bundleID: $0.bundleIdentifier, path: $0.bundleURL?.path)
        }
    }
}

/// What one letter of one side offers right now. The letter panel draws these rows and
/// `initials preview` prints them, so both always agree.
struct LetterPreview: Equatable {
    var letter: String
    /// The pinned app, when the letter has one.
    var binding: Binding?
    /// Running apps the letter cycles through (unpinned letters with cycling on).
    var candidates: [RunningApp]

    var pinned: Bool { binding != nil }
    var isEmpty: Bool { binding == nil && candidates.isEmpty }
    /// "Music", or "Mail +1" when more running apps share the letter.
    var title: String {
        if let binding { return binding.name }
        guard let first = candidates.first else { return "" }
        return candidates.count == 1 ? first.name : "\(first.name) +\(candidates.count - 1)"
    }

    static func row(letter: String, config: Config, side: Side, running: [RunningApp]) -> LetterPreview {
        if let binding = config.bindings(for: side)[letter] {
            return LetterPreview(letter: letter, binding: binding, candidates: [])
        }
        let candidates = config.side(side).cycleUnbound ? cycleCandidates(letter: letter, running: running) : []
        return LetterPreview(letter: letter, binding: nil, candidates: candidates)
    }

    /// Every letter a–z that currently does something on this side (the panel's content).
    static func rows(config: Config, side: Side, running: [RunningApp]) -> [LetterPreview] {
        (UnicodeScalar("a").value...UnicodeScalar("z").value)
            .map { row(letter: String(UnicodeScalar($0)!), config: config, side: side, running: running) }
            .filter { !$0.isEmpty }
    }
}
