import AppKit
import Carbon.HIToolbox

/// Session event tap feeding `KeyEngine`. The callback only classifies (a few
/// comparisons); actions are posted to the main queue so macOS never disables
/// the tap for being slow. A watchdog re-enables it after secure input, sleep
/// or a timeout.
final class EventTap {
    var engine = KeyEngine()
    var onOutput: ((KeyOutput) -> Void)?
    /// Called after each watchdog pass, so the app can refresh its status file when trust or the tap changed.
    var onWatchdog: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?

    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Returns false when Accessibility has not been granted yet.
    @discardableResult
    func start() -> Bool {
        if tap != nil { reenable(); return true }
        refreshLayout()
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, user in
            guard let user else { return Unmanaged.passUnretained(event) }
            return Unmanaged<EventTap>.fromOpaque(user).takeUnretainedValue().handle(type, event)
        }, userInfo: me) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reenable()
            self?.onWatchdog?()
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(reenableFromNotification), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(reenableFromNotification), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(layoutChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        return true
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func reenable() {
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    @objc private func reenableFromNotification() { reenable() }
    @objc private func layoutChanged() { refreshLayout() }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: KeyInput
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            input = .keyDown(code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags.rawValue,
                             isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                             time: Double(event.timestamp) / 1e9)
        case .keyUp:
            input = .keyUp(code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags.rawValue)
        case .flagsChanged:
            input = .flagsChanged(flags: event.flags.rawValue, time: Double(event.timestamp) / 1e9)
        default:
            input = .mouseDown
        }
        let output = engine.handle(input)
        switch output {
        case .pass: return Unmanaged.passUnretained(event)
        case .swallow: return nil
        case .act, .closePicker(swallow: true):
            DispatchQueue.main.async { [weak self] in self?.onOutput?(output) }
            return nil
        case .openPicker, .closePicker(swallow: false):
            DispatchQueue.main.async { [weak self] in self?.onOutput?(output) }
            return Unmanaged.passUnretained(event)
        }
    }

    /// Letters follow the current layout's ASCII keyboard (so AZERTY/Dvorak users
    /// get the letter printed on the key), independent of any Chinese/Japanese IME.
    func refreshLayout() {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = unsafeBitCast(raw, to: CFData.self)
        var map: [UInt16: String] = [:]
        CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for code in UInt16(0)..<UInt16(128) {
                var dead: UInt32 = 0, length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
                guard status == noErr, length == 1 else { continue }
                let s = String(utf16CodeUnits: chars, count: 1).lowercased()
                if let c = s.unicodeScalars.first, ("a"..."z").contains(c), map.values.contains(s) == false { map[code] = s }
            }
        }
        if map.count == 26 { engine.letters = map }
    }
}
