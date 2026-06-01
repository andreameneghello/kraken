import AppKit
import GhosttyKit

// MARK: - NSEvent → Ghostty key helpers

extension NSEvent {
    /// Text suitable for sending to libghostty.
    ///
    /// Filters out function-key PUA ranges and remaps bare control
    /// characters so Ghostty’s own key encoder can handle them.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            // Bare control character — remap without ctrl so Ghostty encodes it.
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            // Function-key PUA range — drop it, Ghostty handles these via keycode.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    /// The unshifted Unicode codepoint for this key event.
    var unshiftedCodepoint: UInt32 {
        guard type == .keyDown || type == .keyUp else { return 0 }
        guard let chars = characters(byApplyingModifiers: []),
              let codepoint = chars.unicodeScalars.first else { return 0 }
        return codepoint.value
    }
}

/// Translate `NSEvent.ModifierFlags` to Ghostty’s modifier enum.
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
    return ghostty_input_mods_e(mods)
}
