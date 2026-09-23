import Foundation

/// Raw keyboard input, reduced to what the engine needs. Built from CGEvents in
/// the app and constructed directly in tests.
enum KeyInput {
    case keyDown(code: UInt16, flags: UInt64, isRepeat: Bool, time: Double)
    case keyUp(code: UInt16, flags: UInt64)
    case flagsChanged(flags: UInt64, time: Double)
    case mouseDown
}

enum KeyOutput: Equatable {
    case pass
    case swallow
    /// Swallow the key and run the letter's action for that side.
    case act(Side, String)
    /// A double-tap of left ⌘ finished: show the picker (the key event passes).
    case openPicker
    /// The picker is open and a key closed it (Esc swallows; other keys pass).
    case closePicker(swallow: Bool)
}

/// Pure, allocation-free decision logic for the event tap. Runs inside the tap
/// callback, so every path is a few comparisons; actions run later on the main queue.
struct KeyEngine {
    // CGEventFlags bits and the device-dependent bits for the physical ⌘ keys.
    static let shift: UInt64 = 0x20000, control: UInt64 = 0x40000, option: UInt64 = 0x80000, command: UInt64 = 0x100000
    static let leftCommandDevice: UInt64 = 0x08, rightCommandDevice: UInt64 = 0x10
    static let escape: UInt16 = 53

    var letters: [UInt16: String] = KeyEngine.ansiLetters
    var rightEnabled = true
    var leftEnabled = true
    var doubleTap = 0.3
    var pickerOpen = false

    private var swallowedUps = Set<UInt16>()
    // Left ⌘ double-tap tracking.
    private var leftHeld = false
    private var tapDownAt: Double?
    private var firstTapUpAt: Double?
    private var interrupted = false

    mutating func handle(_ input: KeyInput) -> KeyOutput {
        switch input {
        case let .keyDown(code, flags, isRepeat, _):
            interrupted = true
            firstTapUpAt = nil
            if pickerOpen {
                pickerOpen = false
                let mods = flags & (Self.command | Self.control | Self.option)
                if mods == 0, let letter = letters[code] {
                    swallowedUps.insert(code)
                    return isRepeat ? .swallow : .act(.left, letter)
                }
                if code == Self.escape {
                    swallowedUps.insert(code)
                    return .closePicker(swallow: true)
                }
                return .closePicker(swallow: false)
            }
            guard rightEnabled, flags & Self.rightCommandDevice != 0,
                  flags & (Self.shift | Self.control | Self.option) == 0,
                  let letter = letters[code] else { return .pass }
            swallowedUps.insert(code)
            return isRepeat ? .swallow : .act(.right, letter)

        case let .keyUp(code, _):
            return swallowedUps.remove(code) != nil ? .swallow : .pass

        case .mouseDown:
            interrupted = true
            firstTapUpAt = nil
            return .pass

        case let .flagsChanged(flags, time):
            return leftCommandChanged(flags: flags, time: time)
        }
    }

    private mutating func leftCommandChanged(flags: UInt64, time: Double) -> KeyOutput {
        let others = flags & (Self.shift | Self.control | Self.option | Self.rightCommandDevice)
        let down = flags & Self.leftCommandDevice != 0
        defer { leftHeld = down }
        guard leftEnabled else { return .pass }
        if others != 0 {
            interrupted = true
            firstTapUpAt = nil
            return .pass
        }
        if down && !leftHeld {
            if let first = firstTapUpAt, time - first > doubleTap { firstTapUpAt = nil }
            tapDownAt = time
            interrupted = false
        } else if !down && leftHeld {
            defer { tapDownAt = nil }
            guard let start = tapDownAt, !interrupted, time - start <= doubleTap else {
                firstTapUpAt = nil
                return .pass
            }
            if firstTapUpAt != nil {
                firstTapUpAt = nil
                pickerOpen = true
                return .openPicker
            }
            firstTapUpAt = time
        }
        return .pass
    }

    /// US ANSI key codes; the app replaces this with the current keyboard layout.
    static let ansiLetters: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]
}
