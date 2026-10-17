import Testing
import VoCoderUIBridge

@Suite struct KeyDecoderTests {
  @Test(arguments: [
    // Printable
    ("a", "a"), ("A", "A"), ("?", "?"), (" ", "Space"), ("é", "é"), ("日", "日"),
    // C0 controls
    ("\u{0}", "Ctrl-Space"), ("\u{1}", "Ctrl-a"), ("\u{3}", "Ctrl-c"), ("\u{10}", "Ctrl-p"),
    ("\u{1A}", "Ctrl-z"), ("\t", "Tab"), ("\n", "Enter"), ("\r", "Enter"), ("\u{8}", "Backspace"),
    ("\u{7F}", "Backspace"), ("\u{1B}", "Esc"), ("\u{1C}", "Ctrl-\\"), ("\u{1D}", "Ctrl-]"),
    // Alt (ESC prefix)
    ("\u{1B}1", "Alt-1"), ("\u{1B}x", "Alt-x"), ("\u{1B}X", "Alt-X"), ("\u{1B} ", "Alt-Space"),
    ("\u{1B}\u{0}", "Ctrl-Alt-Space"), ("\u{1B}\u{1}", "Ctrl-Alt-a"), ("\u{1B}\r", "Alt-Enter"),
    ("\u{1B}\u{7F}", "Alt-Backspace"), ("\u{1B}é", "Alt-é"),
    // Cursor and editing keys, normal and application mode
    ("\u{1B}[A", "ArrowUp"), ("\u{1B}[B", "ArrowDown"), ("\u{1B}[C", "ArrowRight"),
    ("\u{1B}[D", "ArrowLeft"), ("\u{1B}OA", "ArrowUp"), ("\u{1B}[H", "Home"), ("\u{1B}[F", "End"),
    ("\u{1B}[1~", "Home"), ("\u{1B}[4~", "End"), ("\u{1B}[2~", "Insert"), ("\u{1B}[3~", "Delete"),
    ("\u{1B}[5~", "PageUp"), ("\u{1B}[6~", "PageDown"), ("\u{1B}[Z", "Shift-Tab"),
    // Modified cursor keys
    ("\u{1B}[1;5A", "Ctrl-ArrowUp"), ("\u{1B}[1;3D", "Alt-ArrowLeft"),
    ("\u{1B}[1;2C", "Shift-ArrowRight"), ("\u{1B}[1;6B", "Ctrl-Shift-ArrowDown"),
    ("\u{1B}[3;5~", "Ctrl-Delete"),
    // Function keys
    ("\u{1B}OP", "F1"), ("\u{1B}OS", "F4"), ("\u{1B}[15~", "F5"), ("\u{1B}[24~", "F12"),
    ("\u{1B}[1;2P", "Shift-F1"), ("\u{1B}[15;5~", "Ctrl-F5"),
    // CSI-u (Ghostty, kitty) and xterm modifyOtherKeys
    ("\u{1B}[105;5u", "Ctrl-i"), ("\u{1B}[109;5u", "Ctrl-m"), ("\u{1B}[32;7u", "Ctrl-Alt-Space"),
    ("\u{1B}[13;2u", "Shift-Enter"), ("\u{1B}[97;2u", "A"), ("\u{1B}[97;6u", "Ctrl-Shift-a"),
    ("\u{1B}[9;5u", "Ctrl-Tab"), ("\u{1B}[27u", "Esc"), ("\u{1B}[27;5;105~", "Ctrl-i"),
    // Unknown
    ("\u{1B}[99z", "?1b 5b 39 39 7a"),
  ])
  func names(input: String, expected: String) {
    #expect(VCKeyDecoder.keyName(forInput: input) == expected)
  }

  @Test func emptyInput() {
    #expect(VCKeyDecoder.keyName(forInput: "") == "?")
  }
}
