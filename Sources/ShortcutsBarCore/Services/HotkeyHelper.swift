import AppKit
import Carbon.HIToolbox

public enum HotkeyHelper {
    public static func carbonModifiers(from cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if cocoaFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if cocoaFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if cocoaFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        return carbonMods
    }

    public static func string(for keyCode: UInt32, modifiers: UInt32) -> String {
        var str = ""
        if modifiers & UInt32(controlKey) != 0 { str += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { str += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { str += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { str += "⌘" }

        str += keyString(for: keyCode)
        return str
    }

    public static func keyString(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        default: return "Key(\(keyCode))"
        }
    }

    public static func keyEquivalent(for keyCode: UInt32) -> String {
        let key = keyString(for: keyCode)
        if key.count == 1 {
            return key.lowercased()
        }
        switch keyCode {
        case 49: return " " // Space
        case 36: return "\r" // Return
        case 48: return "\t" // Tab
        default: return ""
        }
    }

    public static func cocoaModifiers(from carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonMods & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonMods & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonMods & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}
