import AppKit

/// Shown after a double-tap of left ⌘: every letter that currently does
/// something, with its app. It never becomes key or active, so the app you are
/// in keeps focus; the event tap reads the next key.
final class PickerPanel: NSPanel {
    struct Entry {
        var letter: String
        var title: String
        var icon: NSImage?
        var pinned: Bool
    }

    private let grid = NSStackView()
    private let effect = NSVisualEffectView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        contentView = effect

        let hint = NSTextField(labelWithString: T("按字母切换 · Esc 关闭", "Press a letter · Esc to close"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        let stack = NSStackView(views: [grid, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 14, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func entries(config: Config, side: Side, running: [RunningApp]) -> [Entry] {
        let bindings = config.bindings(for: side)
        let options = config.side(side)
        var result: [Entry] = []
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let letter = String(UnicodeScalar(scalar)!)
            if let b = bindings[letter] {
                let icon = AppCatalog.url(for: b).map { NSWorkspace.shared.icon(forFile: $0.path) }
                result.append(Entry(letter: letter, title: b.name, icon: icon, pinned: true))
            } else if options.cycleUnbound {
                let apps = running.filter { $0.name.lowercased().hasPrefix(letter) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                guard let first = apps.first else { continue }
                let icon = first.path.map { NSWorkspace.shared.icon(forFile: $0) }
                let title = apps.count == 1 ? first.name : "\(first.name) +\(apps.count - 1)"
                result.append(Entry(letter: letter, title: title, icon: icon, pinned: false))
            }
        }
        return result
    }

    func show(_ entries: [Entry], on screen: NSScreen?) {
        fill(entries)
        let target = screen ?? NSScreen.main
        layoutIfNeeded()
        let size = effect.fittingSize
        setContentSize(size)
        if let frame = target?.visibleFrame {
            setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.12))
        }
        orderFrontRegardless()
    }

    func fill(_ entries: [Entry]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let columns = entries.count > 12 ? 3 : 2
        var row: NSStackView?
        for (i, entry) in entries.enumerated() {
            if i % columns == 0 {
                row = NSStackView()
                row!.orientation = .horizontal
                row!.spacing = 10
                grid.addArrangedSubview(row!)
            }
            row!.addArrangedSubview(tile(entry))
        }
        if entries.isEmpty {
            let empty = NSTextField(labelWithString: T("还没有可切换的 app：在设置里给字母指定 app。",
                                                       "Nothing to switch to yet: pin apps to letters in Settings."))
            empty.textColor = .secondaryLabelColor
            grid.addArrangedSubview(empty)
        }
    }

    private func tile(_ entry: Entry) -> NSView {
        let key = NSTextField(labelWithString: entry.letter.uppercased())
        key.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        key.alignment = .center
        key.wantsLayer = true
        key.layer?.cornerRadius = 6
        key.layer?.borderWidth = 1
        key.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        key.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let image = NSImageView(image: entry.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.widthAnchor.constraint(equalToConstant: 28).isActive = true
        image.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 13, weight: entry.pinned ? .medium : .regular)
        title.textColor = entry.pinned ? .labelColor : .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let tile = NSStackView(views: [key, image, title])
        tile.orientation = .horizontal
        tile.spacing = 8
        return tile
    }

    /// Offscreen render for docs and tests; the panel is never ordered in.
    func snapshot(_ entries: [Entry], to url: URL, appearance: NSAppearance?) throws {
        self.appearance = appearance
        fill(entries)
        layoutIfNeeded()
        setContentSize(effect.fittingSize)
        effect.layoutSubtreeIfNeeded()
        // The HUD material only draws behind a real window; use a solid backdrop offscreen.
        effect.material = .windowBackground
        effect.blendingMode = .withinWindow
        try writeRetinaPNG(of: effect, to: url)
    }
}
