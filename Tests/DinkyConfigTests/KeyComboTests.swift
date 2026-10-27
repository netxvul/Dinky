import Carbon.HIToolbox
import Testing
@testable import DinkyConfig

struct KeyComboTests {
    @Test func forms() throws {
        #expect(try KeyCombo("esc") == KeyCombo(key: "esc"))
        #expect(try KeyCombo("r") == KeyCombo(key: "r"))
        #expect(try KeyCombo("ctrl-left") == KeyCombo(modifiers: .ctrl, key: "left"))
        #expect(try KeyCombo("alt-1") == KeyCombo(modifiers: .alt, key: "1"))
        #expect(try KeyCombo("alt-shift-h") == KeyCombo(modifiers: [.alt, .shift], key: "h"))
        #expect(try KeyCombo("alt-shift-semicolon") == KeyCombo(modifiers: [.alt, .shift], key: "semicolon"))
        #expect(try KeyCombo("cmd-ctrl-alt-shift-f12") == KeyCombo(modifiers: [.alt, .ctrl, .cmd, .shift], key: "f12"))
        #expect(try KeyCombo("alt-minus").key == "minus")
        #expect(try KeyCombo("keypad-enter").key == "keypad-enter")
        #expect(try KeyCombo("alt-page-up") == KeyCombo(modifiers: .alt, key: "page-up"))
        #expect(try KeyCombo("page-down") == KeyCombo(key: "page-down"))
        #expect(try KeyCombo("shift-alt-left-bracket").description == "alt-shift-left-bracket")
        #expect(try KeyCombo("hyper-1") == KeyCombo(modifiers: [.alt, .ctrl, .cmd, .shift], key: "1"))
        #expect(try KeyCombo("meh-h") == KeyCombo(modifiers: [.alt, .ctrl, .shift], key: "h"))
        #expect(try KeyCombo("meh-cmd-h") == KeyCombo("hyper-h"), "an alias combines with other modifiers")
        #expect(try KeyCombo("hyper-1").description == "alt-ctrl-cmd-shift-1")
        for name in KeyCombo.keyCodes.keys {
            #expect(try KeyCombo("alt-\(name)").key == name)
            #expect(try KeyCombo(name).key == name)
        }
    }

    @Test func `Key names are kebab-case`() {
        for name in KeyCombo.keyCodes.keys {
            #expect(name == name.lowercased(), "\(name)")
        }
    }

    @Test func `Key codes`() {
        #expect(KeyCombo.keyCodes.count == 100)
        #expect(Set(KeyCombo.keyCodes.values).count == 100, "two names share a keycode")
        #expect(KeyCombo.keyCodes["a"] == UInt16(kVK_ANSI_A))
        #expect(KeyCombo.keyCodes["page-up"] == UInt16(kVK_PageUp))
        #expect(KeyCombo.keyCodes["keypad-enter"] == UInt16(kVK_ANSI_KeypadEnter))
        #expect(KeyCombo.keyCodes["backtick"] == UInt16(kVK_ANSI_Grave))
    }

    @Test(arguments: ["", "alt-", "alt--", "super-a", "hyper", "meh-", "alt-shift-hh", "alt-Semicolon", "-a", "option-a", "pageUp", "alt-page"])
    func `Bad combos`(combo: String) {
        let error = #expect(throws: ConfigError.self) {
            try KeyCombo(combo)
        }
        if let error { #expect("\(error)".contains("'\(combo)'"), "\(error)") }
    }
}
