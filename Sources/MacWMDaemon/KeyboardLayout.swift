import AppKit
import Carbon
import MacWMCore

/// Reads the active keyboard layout so key names follow the keys that type
/// them here, not their US positions. Rebuilt when the input source changes.
enum KeyboardLayout {
    static let changedNotification = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    static func currentTable() -> KeyCodeTable {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return .ansi }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var characters: [String: Int64] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for keyCode in 0..<128 {
                guard let character = Self.character(for: UInt16(keyCode), layout: layout), characters[character] == nil else { continue }
                characters[character] = Int64(keyCode)
            }
        }
        return KeyCodeTable(layoutCharacters: characters)
    }

    private static func character(for keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, units.count, &length, &units
        )
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: units, count: length).lowercased()
        let isPrintable = text.unicodeScalars.allSatisfy { $0.value > 32 }
        guard isPrintable else { return nil }
        return text
    }
}
