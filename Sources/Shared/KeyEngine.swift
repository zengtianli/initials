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
    /// A double-tap of that side's ⌘ finished: show its picker (the key event passes).
    case openPicker(Side)
    /// The picker is open and a key closed it (Esc swallows; other keys pass).
    case closePicker(swallow: Bool)
}

/// How one physical ⌘ key triggers. Both ⌘ keys can use either or both.
struct Trigger: Equatable {
    /// Hold this ⌘ and press a letter.
    var hold = false
    /// Tap this ⌘ twice quickly, then press a letter in the picker.
    var doubleTap = false
    /// Hold intercepts every letter (unpinned ones cycle); otherwise only `pinned`.
    var anyLetter = false
    /// Bit n set = letter "a"+n is pinned.
    var pinned: UInt32 = 0

    static func mask(_ letters: some Sequence<String>) -> UInt32 {
        letters.reduce(0) { m, l in
            guard let v = l.unicodeScalars.first?.value, v >= 97, v <= 122 else { return m }
            return m | (1 << (v - 97))
        }
    }
}

/// Pure, allocation-free decision logic for the event tap. Runs inside the tap
/// callback, so every path is a few comparisons; actions run later on the main queue.
struct KeyEngine {
    // CGEventFlags bits and the device-dependent bits for the physical ⌘ keys.
    static let shift: UInt64 = 0x20000, control: UInt64 = 0x40000, option: UInt64 = 0x80000, command: UInt64 = 0x100000
    static let leftCommandDevice: UInt64 = 0x08, rightCommandDevice: UInt64 = 0x10
    static let escape: UInt16 = 53

    var letters: [UInt16: String] = KeyEngine.ansiLetters { didSet { letterBits = Self.bits(letters) } }
    /// Key code → letter bit (0 = not a letter), so the common path never touches strings.
    private var letterBits = KeyEngine.bits(KeyEngine.ansiLetters)
    /// Defaults match a fresh config: right ⌘ holds, left ⌘ double-taps.
    var right = Trigger(hold: true, anyLetter: true)
    var left = Trigger(doubleTap: true)
    var doubleTap = 0.3
    var pickerOpen = false
    private(set) var pickerSide = Side.left

    private var swallowedUps = Set<UInt16>()
    private var rightTap = TapState(), leftTap = TapState()

    private struct TapState {
        var held = false
        var downAt: Double?
        var firstUpAt: Double?
        var interrupted = false

        mutating func interrupt() {
            interrupted = true
            firstUpAt = nil
        }

        /// One ⌘ key's double-tap tracking; true when the second quick tap ends.
        /// Any other modifier, key or click in between cancels.
        mutating func changed(down: Bool, others: Bool, time: Double, window: Double) -> Bool {
            defer { held = down }
            if others {
                interrupt()
                return false
            }
            if down && !held {
                if let first = firstUpAt, time - first > window { firstUpAt = nil }
                downAt = time
                interrupted = false
            } else if !down && held {
                defer { downAt = nil }
                guard let start = downAt, !interrupted, time - start <= window else {
                    firstUpAt = nil
                    return false
                }
                if firstUpAt != nil {
                    firstUpAt = nil
                    return true
                }
                firstUpAt = time
            }
            return false
        }
    }

    mutating func handle(_ input: KeyInput) -> KeyOutput {
        switch input {
        case let .keyDown(code, flags, isRepeat, _):
            rightTap.interrupt()
            leftTap.interrupt()
            if pickerOpen {
                pickerOpen = false
                let mods = flags & (Self.command | Self.control | Self.option)
                if mods == 0, let letter = letters[code] {
                    swallowedUps.insert(code)
                    return isRepeat ? .swallow : .act(pickerSide, letter)
                }
                if code == Self.escape {
                    swallowedUps.insert(code)
                    return .closePicker(swallow: true)
                }
                return .closePicker(swallow: false)
            }
            guard flags & (Self.shift | Self.control | Self.option) == 0, code < 128 else { return .pass }
            let bit = letterBits[Int(code)]
            guard bit != 0 else { return .pass }
            let side: Side
            if right.hold, flags & Self.rightCommandDevice != 0, right.anyLetter || right.pinned & bit != 0 { side = .right }
            else if left.hold, flags & Self.leftCommandDevice != 0, left.anyLetter || left.pinned & bit != 0 { side = .left }
            else { return .pass }
            swallowedUps.insert(code)
            return isRepeat ? .swallow : .act(side, letters[code]!)

        case let .keyUp(code, _):
            return swallowedUps.remove(code) != nil ? .swallow : .pass

        case .mouseDown:
            rightTap.interrupt()
            leftTap.interrupt()
            return .pass

        case let .flagsChanged(flags, time):
            let mods = flags & (Self.shift | Self.control | Self.option)
            let r = flags & Self.rightCommandDevice != 0, l = flags & Self.leftCommandDevice != 0
            // Always track press state so turning a trigger on mid-press never misfires.
            let rightDone = rightTap.changed(down: r, others: mods != 0 || l, time: time, window: doubleTap)
            let leftDone = leftTap.changed(down: l, others: mods != 0 || r, time: time, window: doubleTap)
            let side: Side
            if rightDone && right.doubleTap { side = .right }
            else if leftDone && left.doubleTap { side = .left }
            else { return .pass }
            pickerOpen = true
            pickerSide = side
            return .openPicker(side)
        }
    }

    private static func bits(_ letters: [UInt16: String]) -> [UInt32] {
        var table = [UInt32](repeating: 0, count: 128)
        for (code, letter) in letters where code < 128 { table[Int(code)] = Trigger.mask([letter]) }
        return table
    }

    /// US ANSI key codes; the app replaces this with the current keyboard layout.
    static let ansiLetters: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]
}
